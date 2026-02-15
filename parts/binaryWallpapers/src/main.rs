use ab_glyph::FontRef;
use binary_wallpapers::modules::letterize::CharacterGrid;
use binary_wallpapers::Color;
use clap::Parser;
use flate2::Compression;
use std::io::Write;
use std::path::PathBuf;

#[derive(Parser)]
#[command(version, about, long_about = None)]
struct Arguments {
    #[arg(short, long)]
    image: PathBuf,
    #[arg(short, long)]
    data: PathBuf,
    #[arg(short, long)]
    primary_color: Color,
    #[arg(short, long)]
    secondary_color: Color,
    #[arg(short, long)]
    output: PathBuf,
}

fn main() {
    let args = Arguments::parse();

    println!("Loading image: {:?}", args.image);
    println!("Loading data: {:?}", args.data);
    println!("Writing output to: {:?}", args.output);

    let mut image = image::open(&args.image)
        .unwrap_or_else(|_| {
            eprintln!("Failed to open image file: {:?}", args.image);
            std::process::exit(1);
        })
        .to_rgb8();

    for pixel in image.pixels_mut() {
        if pixel[0] == 0xFF && pixel[1] == 0 && pixel[2] == 0 {
            pixel[0] = args.primary_color.r;
            pixel[1] = args.primary_color.g;
            pixel[2] = args.primary_color.b;
        }
        if pixel[0] == 0 && pixel[1] == 0xFF && pixel[2] == 0 {
            pixel[0] = args.secondary_color.r;
            pixel[1] = args.secondary_color.g;
            pixel[2] = args.secondary_color.b;
        }
    }

    let font = FontRef::try_from_slice(include_bytes!("../JetBrainsMono-Regular.ttf")).unwrap();

    let font_scale = 45.0;
    let actual_size = 35.0;
    let x_correction = 0;
    let y_correction = -10;

    let letter_scale = {
        let letter_scale_0 = imageproc::drawing::text_size(font_scale, &font, "0");
        let letter_scale_1 = imageproc::drawing::text_size(font_scale, &font, "1");
        letter_scale_0.max(letter_scale_1)
    };

    let target_width = 3840;
    let target_height = 2160;

    let mut buffer = CharacterGrid::new(
        target_width / letter_scale.0 as u32,
        target_height / letter_scale.1 as u32,
    );
    for x in 0..buffer.width() {
        for y in 0..buffer.height() {
            let character = buffer.character_mut(x, y);
            character.letter = 'X';
        }
    }
    let data = std::fs::read(&args.data).unwrap_or_else(|_| {
        eprintln!("Failed to read data file: {:?}", args.data);
        vec![]
    });
    let mut gz_data = flate2::write::GzEncoder::new(Vec::new(), Compression::best());
    gz_data.write(data.as_slice()).unwrap();
    let gz_data = gz_data.finish().unwrap();
    let delta = buffer.datarize_from_slice(gz_data.as_slice());
    if delta > 0 {
        println!("Grid is too small by {} characters", delta);
    }

    let letter_size_on_original_image_width = image.width() / buffer.width() as u32;
    let letter_size_on_original_image_height = image.height() / buffer.height() as u32;

    buffer.colorize_from_image(
        &image,
        letter_size_on_original_image_width as usize,
        letter_size_on_original_image_height as usize,
    );

    for x in 0..buffer.width() {
        for y in 0..buffer.height() {
            let character = buffer.character_mut(x, y);
            if character.fg_color == character.bg_color {
                if character.fg_color == Color::WHITE {
                    character.fg_color.r -= 1;
                    character.fg_color.g -= 1;
                    character.fg_color.b -= 1;
                } else {
                    character.fg_color.r += 1;
                    character.fg_color.g += 1;
                    character.fg_color.b += 1;
                }
            }
        }
    }

    let img = buffer.to_image_spaced(
        letter_scale.0,
        letter_scale.1,
        &font,
        actual_size,
        x_correction,
        y_correction,
    );
    img.save(&args.output).unwrap_or_else(|_| {
        eprintln!("Failed to save the output image to: {:?}", args.output);
        std::process::exit(1);
    });
}
