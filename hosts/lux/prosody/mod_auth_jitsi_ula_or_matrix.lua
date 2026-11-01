-- mod_auth_jitsi_ula_or_matrix: room creation only for the fleet ULA and Matrix users (hosts/lux/jitsi.nix)
--
-- Auth provider for the *main* Jitsi VirtualHost (meet.<domain>) in secure-domain mode.
-- Only sessions authenticated here get a JID @meet.<domain>, and only those may create a
-- conference (jicofo: authentication.type = XMPP, login-url = meet.<domain>, i.e. jicofo's
-- XMPPDomainAuthAuthority treats every requester whose JID domain is meet.<domain> as
-- authenticated). Everybody else must use the anonymous guest.meet.<domain> host.
--
-- A session passes SASL ANONYMOUS here iff
--   1. its client address (session.ip) is inside one of `jitsi_trusted_prefixes`
--      (the fleet's WireGuard ULA /64s), or
--   2. it carries a JWT (Element's "openidtoken-jwt" widget auth, ?token=... on the
--      websocket/BOSH URL) whose context.matrix.token is an OpenID token that our own
--      homeserver confirms (`jitsi_matrix_backend`):
--        "userinfo": GET <jitsi_matrix_userinfo_url>?access_token=... (Synapse's
--                    /_matrix/federation/v1/openid/userinfo, reached directly, not via
--                    the public proxy) and require sub == "@...:<jitsi_matrix_server_name>"
--        "uvs":      delegate to mod_auth_matrix_user_verification (matrix-org), which
--                    asks the matrix-user-verification-service (OpenID + room membership)
--        "none":     no Matrix path, ULA only
-- Everything else fails SASL (not-authorized); there is no password mechanism at all.
--
-- session.ip: for websocket/BOSH sessions prosody sets it from request.ip, which mod_http
-- derives from X-Forwarded-For only when the TCP peer is in the global `trusted_proxies`
-- (prosody plugins/mod_http.lua get_forwarded_connection_info, legacy X-Forwarded-For
-- mode: the right-most address that is not a trusted proxy wins; if every hop is trusted
-- the peer address itself is kept). mod_websocket.lua: `session.ip = request.ip`,
-- mod_bosh.lua: `ip = request.ip`. For direct c2s TCP it is the socket peer.
--
-- Prosody APIs used (prosody 13.0):
--   util.sasl.new(realm, profile)            -- profile.anonymous(sasl, username, realm)
--   util.sasl.registerMechanism(name, backends, fn) -- same ANONYMOUS override as jitsi's
--                                            -- mod_auth_jitsi-anonymous / mod_auth_token
--   module:provides("auth", provider)       -- core/usermanager selects the provider whose
--                                            -- name == `authentication` ("jitsi_ula_or_matrix")
--   module:depends(name), module:get_host_items("auth-provider")
--   util.ip.new_ip / parse_cidr / match
--   net.http.request(url, opts, cb) + util.async.waiter() (SASL runs in an async thread,
--                                            -- as in mod_auth_matrix_user_verification)

local new_sasl = require "util.sasl".new;
local sasl = require "util.sasl";
local generate_uuid = require "util.uuid".generate;
local ip_util = require "util.ip";
local http = require "net.http";
local async = require "util.async";
local json = require "util.json";
local base64_decode = require "util.encodings".base64.decode;
local urlencode = require "util.http".urlencode;

local host = module.host;
local sessions = prosody.full_sessions;

-- ?previd= / ?token= / ?room= from the websocket/BOSH URL (global module of jitsi-meet-prosody)
module:depends("jitsi_session");

local trusted_nets = {};
for _, cidr in ipairs(module:get_option_array("jitsi_trusted_prefixes", {})) do
    local net, bits = ip_util.parse_cidr(cidr);
    if not net or not bits then
        error("jitsi_trusted_prefixes: invalid prefix " .. tostring(cidr));
    end
    table.insert(trusted_nets, { net = net, bits = bits });
end
if #trusted_nets == 0 then
    module:log("warn", "jitsi_trusted_prefixes is empty: no address-based room creation");
end

local backend = module:get_option_string("jitsi_matrix_backend", "none");
local userinfo_url = module:get_option_string("jitsi_matrix_userinfo_url");
local server_name = module:get_option_string("jitsi_matrix_server_name");

if backend == "userinfo" and (not userinfo_url or not server_name) then
    error("jitsi_matrix_backend = userinfo needs jitsi_matrix_userinfo_url and jitsi_matrix_server_name");
end

local uvs_provider;
if backend == "uvs" then
    -- Loads matrix-org's provider on this host. It registers itself as auth provider
    -- "matrix_user_verification"; usermanager ignores it (authentication names us), we
    -- only borrow its SASL handler. Its options (uvs_base_url, uvs_auth_token, ...) are
    -- read from this VirtualHost's config.
    module:depends("auth_matrix_user_verification");
    for _, item in ipairs(module:get_host_items("auth-provider")) do
        if item.name == "matrix_user_verification" then uvs_provider = item; end
    end
    if not uvs_provider then
        error("mod_auth_matrix_user_verification did not provide its auth provider (uvs_base_url unset?)");
    end
end

local function is_trusted(session)
    local addr = session.ip and ip_util.new_ip(session.ip);
    if not addr then return false; end
    for _, n in ipairs(trusted_nets) do
        if ip_util.match(addr, n.net, n.bits) then return true; end
    end
    return false;
end

-- payload of a JWT, signature NOT checked (Element signs with the dummy key "notused";
-- the OpenID token inside is what gets verified)
local function jwt_payload(token)
    local part = type(token) == "string" and token:match("^[%w_-]+%.([%w_-]+)%.[%w_-]*$");
    if not part then return nil; end
    part = part:gsub("-", "+"):gsub("_", "/");
    part = part .. string.rep("=", (4 - #part % 4) % 4);
    local raw = base64_decode(part);
    return raw and json.decode(raw);
end

-- the Matrix user ID if `openid_token` is valid on our homeserver, else nil
local function verify_openid_userinfo(openid_token)
    if type(openid_token) ~= "string" or openid_token == "" then return nil; end
    local wait, done = async.waiter();
    local sub;
    http.request(userinfo_url .. "?access_token=" .. urlencode(openid_token), {}, function(body, code)
        if code == 200 then
            local data = json.decode(body);
            if type(data) == "table" and type(data.sub) == "string" then sub = data.sub; end
        end
        done();
    end);
    wait();
    local suffix = ":" .. server_name;
    if sub and #sub > #suffix and sub:sub(-#suffix) == suffix then return sub; end
    return nil;
end

-- jitsi-anonymous' username choice: keep the old random username on ?previd= resumption
local function pick_username(self, session, message)
    if session.previd ~= nil then
        for _, s in pairs(sessions) do
            if s.resumption_token == session.previd then
                self.username = s.username;
                return;
            end
        end
    end
    self.username = message;
end

local provider = {};

function provider.test_password() return nil, "Password based auth not supported"; end
function provider.get_password() return nil; end
function provider.set_password() return nil, "Set password not supported"; end
function provider.user_exists() return nil; end
function provider.create_user() return nil; end
function provider.delete_user() return nil; end

function provider.get_sasl_handler(session)
    -- decided per SASL attempt, not cached: get_sasl_handler runs at <stream:features>,
    -- after mod_websocket/mod_bosh have set session.ip
    if not is_trusted(session) and backend == "uvs" then
        return uvs_provider.get_sasl_handler(session);
    end

    local function anonymous_cb(self, message)
        if is_trusted(session) then
            -- token-free path; drop any URL token so no jitsi module treats the session
            -- as JWT-authenticated
            session.auth_token = nil;
            pick_username(self, session, message);
            module:log("info", "room-creating session from trusted address %s", session.ip);
            return true;
        end

        if backend == "userinfo" and session.auth_token then
            local claims = jwt_payload(session.auth_token);
            local matrix = type(claims) == "table" and type(claims.context) == "table"
                and claims.context.matrix;
            local user_id = type(matrix) == "table" and verify_openid_userinfo(matrix.token);
            if user_id then
                session.jitsi_matrix_user_id = user_id;
                -- display name/avatar only (not context.features: the JWT is unsigned)
                if type(claims.context.user) == "table" then
                    session.jitsi_meet_context_user = claims.context.user;
                end
                pick_username(self, session, message);
                module:log("info", "room-creating session for Matrix user %s from %s", user_id, session.ip);
                return true;
            end
        end

        session.auth_token = nil;
        module:log("info", "rejecting main-domain login from %s", tostring(session.ip));
        return false, "not-authorized", "Room creation is restricted";
    end

    return new_sasl(host, { anonymous = anonymous_cb });
end

module:provides("auth", provider);

-- Identical to jitsi's ANONYMOUS override (mod_auth_jitsi-anonymous.lua / mod_auth_token.lua):
-- the profile may set self.username (resumption), otherwise a fresh UUID. Registration is
-- global and last-wins; all variants behave the same.
sasl.registerMechanism("ANONYMOUS", { "anonymous" }, function(self, message)
    local username = generate_uuid();
    local result, err, msg = self.profile.anonymous(self, username, self.realm);
    if result == true then
        if self.username == nil then self.username = username; end
        return "success";
    end
    return "failure", err, msg;
end);

module:hook("pre-resource-unbind", function(e)
    prosody.events.fire_event("jitsi-pre-session-unbind", {
        jid = e.session.full_jid, session = e.session, error = e.error,
    });
end, 11);
