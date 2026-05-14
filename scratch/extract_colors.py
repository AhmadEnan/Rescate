import sys
from PIL import Image
from collections import Counter

def get_dominant_colors(image_path, num_colors=10):
    try:
        img = Image.open(image_path).convert("RGB")
        # Resize to speed up processing
        img = img.resize((150, 150))
        pixels = list(img.getdata())
        
        # Count colors
        color_counts = Counter(pixels)
        
        print(f"--- Colors for {image_path} ---")
        for color, count in color_counts.most_common(num_colors):
            hex_color = '#{:02x}{:02x}{:02x}'.format(color[0], color[1], color[2])
            print(f"Color: {hex_color}, Count: {count}")
    except Exception as e:
        print(f"Error processing {image_path}: {e}")

images = [
    r"f:\Rescate\Onboarding 1 - Set Language.png",
    r"f:\Rescate\Onboarding 2.png",
    r"f:\Rescate\Onboarding 3.png",
    r"f:\Rescate\Educational Tab.png",
    r"f:\Rescate\GPS (2).png",
    r"f:\Rescate\AI.png",
    r"f:\Rescate\Logo.png"
]

for img in images:
    get_dominant_colors(img)
