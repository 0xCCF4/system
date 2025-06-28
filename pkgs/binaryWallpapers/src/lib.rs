use image::Rgb;
use std::str::FromStr;

pub mod modules {
    pub mod letterize;
}

#[derive(Clone, Copy, Default, PartialEq, Eq)]
pub struct Color {
    pub r: u8,
    pub g: u8,
    pub b: u8,
}

impl Color {
    pub const fn new(r: u8, g: u8, b: u8) -> Color {
        Color { r, g, b }
    }

    /*pub fn random() -> Color {
        let mut rng = rand::rng();
        Color::new(
            rng.random_range(0..255),
            rng.random_range(0..255),
            rng.random_range(0..255),
        )
    }*/

    pub const WHITE: Color = Color::new(255, 255, 255);
    pub const BLACK: Color = Color::new(0, 0, 0);
}

impl From<Color> for Rgb<u8> {
    fn from(color: Color) -> Self {
        Rgb([color.r, color.g, color.b])
    }
}

impl From<Rgb<u8>> for Color {
    fn from(rgb: Rgb<u8>) -> Self {
        Color {
            r: rgb[0],
            g: rgb[1],
            b: rgb[2],
        }
    }
}

impl FromStr for Color {
    type Err = &'static str;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        let value = s.trim_start_matches('#');
        let r = u8::from_str_radix(&value[0..2], 16).map_err(|_| "invalid red component")?;
        let g = u8::from_str_radix(&value[2..4], 16).map_err(|_| "invalid green component")?;
        let b = u8::from_str_radix(&value[4..6], 16).map_err(|_| "invalid blue component")?;
        Ok(Color::new(r, g, b))
    }
}
