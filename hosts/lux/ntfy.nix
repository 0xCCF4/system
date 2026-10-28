# Self-hosted push (ntfy as UnifiedPush distributor and Matrix push gateway)
#
# TODO, not implemented yet:
# - container `ntfy` (services.ntfy-sh), like the others with container-common.nix, behind
#   caddy (mine.services.caddyProxy.routes), e.g. https://ntfy.<domain>
# - ntfy serves the Matrix push gateway endpoint (/_matrix/push/v1/notify): Android
#   clients with UnifiedPush (ntfy app as distributor; Element, SchildiChat, FluffyChat)
#   register it, synapse -> ntfy then stays container to container
# - firewall (firewall.nix): caddy -> ntfy, synapse -> ntfy; ntfy itself needs no internet
#   for Android
# - iOS can not be served without APNs: the clients keep the vendor gateway (matrix.org
#   for Element), ntfy's iOS app would need upstream-base-url = ntfy.sh (message IDs only)
# - auth: ntfy access control (deny-all by default, tokens per user/topic)
# - afterwards: synapse's internet access (firewall.nix, push gateways + URL previews)
#   could shrink to URL previews only, or none with url_preview_enabled = false
# - push.include_content = false is already set (matrix-synapse.nix), gateways only get IDs
{ ... }:
{ }
