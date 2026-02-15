use crate::Color;
use ab_glyph::Font;
use image::{GenericImageView, ImageBuffer};

#[derive(Clone)]
pub struct Character {
    pub fg_color: Color,
    pub bg_color: Color,
    pub letter: char,
}

impl Default for Character {
    fn default() -> Self {
        Self {
            fg_color: Color::WHITE,
            bg_color: Color::BLACK,
            letter: ' ',
        }
    }
}

#[derive(Clone)]
pub struct CharacterGrid {
    characters: Vec<Character>,
    width: u32,
    height: u32,
}

impl CharacterGrid {
    pub fn new(width: u32, height: u32) -> Self {
        Self {
            characters: vec![Character::default(); (width * height) as usize],
            width,
            height,
        }
    }
    pub fn character(&self, x: u32, y: u32) -> &Character {
        &self.characters[(y * self.width + x) as usize]
    }
    pub fn character_mut(&mut self, x: u32, y: u32) -> &mut Character {
        &mut self.characters[(y * self.width + x) as usize]
    }

    pub fn colorize_from_image(
        &mut self,
        image: &image::RgbImage,
        letter_width: usize,
        letter_height: usize,
    ) {
        for x in 0..self.width {
            for y in 0..self.height {
                let bounding_box = image.view(
                    x as u32 * letter_width as u32,
                    y as u32 * letter_height as u32,
                    letter_width as u32,
                    letter_height as u32,
                );

                let average_color = bounding_box.pixels().fold((0.0, 0.0, 0.0), |acc, pixel| {
                    (
                        acc.0 + pixel.2[0] as f32,
                        acc.1 + pixel.2[1] as f32,
                        acc.2 + pixel.2[2] as f32,
                    )
                });
                let average_color = (
                    average_color.0 / (letter_width * letter_height) as f32,
                    average_color.1 / (letter_width * letter_height) as f32,
                    average_color.2 / (letter_width * letter_height) as f32,
                );

                let color = Color::new(
                    average_color.0 as u8,
                    average_color.1 as u8,
                    average_color.2 as u8,
                );

                self.character_mut(x, y).fg_color = color;
            }
        }
    }

    pub const fn width(&self) -> u32 {
        self.width
    }

    pub const fn height(&self) -> u32 {
        self.height
    }

    pub fn to_image_spaced(
        &self,
        letter_width: u32,
        letter_height: u32,
        font: &impl Font,
        font_scale: f32,
        x_correction: i32,
        y_correction: i32,
    ) -> image::ImageBuffer<image::Rgb<u8>, Vec<u8>> {
        let mut img = ImageBuffer::new(
            self.width as u32 * letter_width as u32,
            self.height as u32 * letter_height as u32,
        );

        for x in 0..self.width {
            for y in 0..self.height {
                let character = self.character(x, y);
                let letter = character.letter;
                let fg_color = character.fg_color;
                let bg_color = character.bg_color;

                let letter_size =
                    imageproc::drawing::text_size(font_scale, font, letter.to_string().as_str());

                let letter_start_x = (x * letter_width) as i32;
                let letter_start_y = (y * letter_height) as i32;

                let startx_offset = (letter_width as i32 - letter_size.0 as i32) / 2;
                let starty_offset = (letter_height as i32 - letter_size.1 as i32) / 2;

                let actual_letter_start_x = letter_start_x + startx_offset + x_correction;
                let actual_letter_start_y = letter_start_y + starty_offset + y_correction;

                for i in 0..letter_width {
                    for j in 0..letter_height {
                        let actual_x = letter_start_x + i as i32;
                        let actual_y = letter_start_y + j as i32;

                        if actual_y < 0 || actual_x < 0 {
                            continue;
                        }

                        let pixel = img.get_pixel_mut_checked(actual_x as u32, actual_y as u32);
                        if let Some(pixel) = pixel {
                            *pixel = image::Rgb([bg_color.r, bg_color.g, bg_color.b]);
                        }
                    }
                }
                // img.get_pixel_mut_checked((x * letter_width) as u32, (y * letter_height) as u32).map(|pixel| *pixel = image::Rgb([fg_color.r, fg_color.g, fg_color.b]));

                imageproc::drawing::draw_text_mut(
                    &mut img,
                    fg_color.into(),
                    actual_letter_start_x,
                    actual_letter_start_y,
                    font_scale,
                    font,
                    letter.to_string().as_str(),
                );
            }
        }

        img
    }

    pub fn datarize_from_slice(&mut self, data: &[u8]) -> i32 {
        for (i, data) in data.iter().enumerate() {
            for bin in (0..8).rev() {
                self.characters.get_mut(i * 8 + bin).map(|character| {
                    character.letter = if data & (1 << bin) != 0 { '1' } else { '0' };
                });
            }
        }
        let data_space = self.width * self.height;
        let target_space = data.len() * 8;

        (target_space as i32 - data_space as i32) as i32
    }
}
