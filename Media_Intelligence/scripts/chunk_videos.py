#!/usr/bin/env python3
"""
Chunk MP4 files into segments below 100 MB each.
First ensures audio is encoded with Opus codec for Snowflake AI FUNCTIONS and Gemini Pro compatibility.
Uses ffmpeg to split videos efficiently without re-encoding.
"""

import os
import subprocess
import json
from pathlib import Path
from typing import List, Tuple, Optional


MAX_CHUNK_SIZE_MB = 100
MAX_CHUNK_SIZE_BYTES = MAX_CHUNK_SIZE_MB * 1024 * 1024


def get_audio_codec(filepath: str) -> Optional[str]:
    """Get the audio codec of a video file."""
    cmd = [
        'ffprobe',
        '-v', 'error',
        '-select_streams', 'a:0',
        '-show_entries', 'stream=codec_name',
        '-of', 'json',
        filepath
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, check=True)
    data = json.loads(result.stdout)

    if 'streams' in data and len(data['streams']) > 0:
        return data['streams'][0].get('codec_name')
    return None


def ensure_compatible_encoding(input_file: str, temp_dir: Path) -> str:
    """
    Ensure video has Opus audio codec for Snowflake AI FUNCTIONS and Gemini Pro compatibility.
    Re-encodes audio to Opus if needed, keeping video stream as-is.

    Args:
        input_file: Path to input video file
        temp_dir: Directory for temporary encoded files

    Returns:
        Path to compatible video (original if already compatible, or newly encoded file)
    """
    input_path = Path(input_file)
    audio_codec = get_audio_codec(str(input_path))

    # Check if already using Opus
    if audio_codec == 'opus':
        print(f"   ✓ Audio already encoded with Opus")
        return str(input_path)

    # Need to re-encode audio
    print(f"   ⚙️  Re-encoding audio from {audio_codec or 'unknown'} to Opus...")
    temp_dir.mkdir(parents=True, exist_ok=True)

    output_file = temp_dir / f"{input_path.stem}_opus{input_path.suffix}"

    cmd = [
        'ffmpeg',
        '-y',
        '-i', str(input_path),
        '-c:v', 'copy',      # Copy video stream as-is
        '-c:a', 'libopus',   # Re-encode audio to Opus
        str(output_file)
    ]

    subprocess.run(cmd, capture_output=True, check=True)
    print(f"   ✓ Audio re-encoded to Opus")

    return str(output_file)


def get_video_duration(filepath: str) -> float:
    """Get video duration in seconds using ffprobe."""
    cmd = [
        'ffprobe',
        '-v', 'error',
        '-show_entries', 'format=duration',
        '-of', 'json',
        filepath
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, check=True)
    data = json.loads(result.stdout)
    return float(data['format']['duration'])


def calculate_chunk_duration(filepath: str, filesize_bytes: int) -> float:
    """Calculate optimal chunk duration to keep segments under MAX_CHUNK_SIZE_MB."""
    duration = get_video_duration(filepath)
    bitrate = filesize_bytes / duration  # bytes per second

    # Calculate duration that fits in MAX_CHUNK_SIZE_BYTES
    # Leave 5% safety margin for overhead
    chunk_duration = (MAX_CHUNK_SIZE_BYTES * 0.95) / bitrate

    return chunk_duration


def chunk_video(input_file: str, output_dir: str = None, temp_dir: str = None) -> List[str]:
    """
    Split a video file into chunks below MAX_CHUNK_SIZE_MB.
    First ensures audio is encoded with Opus codec for compatibility.

    Args:
        input_file: Path to input MP4 file
        output_dir: Directory for output files (default: same as input)
        temp_dir: Directory for temporary encoded files (default: ./temp_encoded)

    Returns:
        List of created chunk file paths
    """
    input_path = Path(input_file)
    original_name = input_path.name

    # Set output directory
    if output_dir is None:
        output_dir = input_path.parent
    else:
        output_dir = Path(output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)

    # Set temp directory for encoding
    if temp_dir is None:
        temp_dir = input_path.parent / "temp_encoded"
    else:
        temp_dir = Path(temp_dir)

    print(f"\n📹 Processing: {original_name}")

    # Step 1: Ensure compatible encoding (Opus audio)
    compatible_file = ensure_compatible_encoding(str(input_path), temp_dir)
    compatible_path = Path(compatible_file)

    # Check file size after encoding
    filesize = compatible_path.stat().st_size
    print(f"   File size: {filesize / (1024**2):.1f} MB")

    # If file is already under the limit, just copy it to output and skip chunking
    if filesize <= MAX_CHUNK_SIZE_BYTES:
        if compatible_file != str(input_path):
            # Copy the re-encoded file to output directory
            output_file = output_dir / original_name
            subprocess.run(['cp', str(compatible_path), str(output_file)], check=True)
            print(f"   ✓ File is under {MAX_CHUNK_SIZE_MB} MB, copied to output directory")
            return [str(output_file)]
        else:
            print(f"   ✓ File is under {MAX_CHUNK_SIZE_MB} MB, no chunking needed")
            return []

    # Step 2: Calculate chunk duration
    chunk_duration = calculate_chunk_duration(str(compatible_path), filesize)
    print(f"   Chunk duration: {chunk_duration:.1f} seconds")

    # Step 3: Create output pattern (use original name without _opus suffix)
    base_name = input_path.stem
    output_pattern = output_dir / f"{base_name}_chunk_%03d.mp4"

    # Step 4: Split the video
    cmd = [
        'ffmpeg',
        '-i', str(compatible_path),
        '-c', 'copy',  # Copy codecs without re-encoding (fast!)
        '-map', '0',   # Copy all streams
        '-f', 'segment',
        '-segment_time', str(chunk_duration),
        '-reset_timestamps', '1',
        '-y',  # Overwrite existing files
        str(output_pattern)
    ]

    print(f"   Splitting video...")
    subprocess.run(cmd, capture_output=True, check=True)

    # Clean up temp file if we created one
    if compatible_file != str(input_path):
        compatible_path.unlink()

    # Find all created chunks
    chunks = sorted(output_dir.glob(f"{base_name}_chunk_*.mp4"))

    # Verify chunk sizes
    print(f"   Created {len(chunks)} chunks:")
    for chunk in chunks:
        size_mb = chunk.stat().st_size / (1024**2)
        print(f"      • {chunk.name}: {size_mb:.1f} MB")

    return [str(c) for c in chunks]


def chunk_all_videos(directory: str = ".", output_dir: str = None, pattern: str = "*.mp4") -> dict:
    """
    Chunk all MP4 files in a directory.
    First ensures all videos have Opus audio codec for compatibility.

    Args:
        directory: Directory to scan for videos
        output_dir: Directory for output chunks (default: subdirectory 'chunks')
        pattern: File pattern to match (default: "*.mp4")

    Returns:
        Dictionary mapping input files to their chunks
    """
    directory = Path(directory)

    # Default output directory
    if output_dir is None:
        output_dir = directory / "chunks"

    # Temp directory for encoding
    temp_dir = directory / "temp_encoded"

    # Find all MP4 files
    video_files = list(directory.glob(pattern))

    if not video_files:
        print(f"No video files found matching '{pattern}' in {directory}")
        return {}

    print(f"Found {len(video_files)} video file(s)")
    print(f"Output directory: {output_dir}")

    results = {}
    for video_file in video_files:
        try:
            chunks = chunk_video(str(video_file), str(output_dir), str(temp_dir))
            if chunks:
                results[str(video_file)] = chunks
        except subprocess.CalledProcessError as e:
            print(f"✗ Error processing {video_file.name}: {e}")
        except Exception as e:
            print(f"✗ Unexpected error with {video_file.name}: {e}")

    # Clean up temp directory if it exists and is empty
    if temp_dir.exists():
        try:
            temp_dir.rmdir()
        except OSError:
            pass  # Directory not empty, leave it

    return results


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(
        description=f"Encode MP4 files with Opus audio for Snowflake/Gemini compatibility, then chunk into segments below {MAX_CHUNK_SIZE_MB} MB"
    )
    parser.add_argument(
        'input',
        nargs='?',
        default='.',
        help='Input file or directory (default: current directory)'
    )
    parser.add_argument(
        '-o', '--output',
        help='Output directory for chunks (default: ./chunks or same dir as input)'
    )
    parser.add_argument(
        '--max-size',
        type=int,
        default=MAX_CHUNK_SIZE_MB,
        help=f'Maximum chunk size in MB (default: {MAX_CHUNK_SIZE_MB})'
    )

    args = parser.parse_args()

    # Update max chunk size if specified
    MAX_CHUNK_SIZE_MB = args.max_size
    MAX_CHUNK_SIZE_BYTES = MAX_CHUNK_SIZE_MB * 1024 * 1024

    input_path = Path(args.input)

    if input_path.is_file():
        # Single file
        chunk_video(str(input_path), args.output)
    elif input_path.is_dir():
        # Directory
        results = chunk_all_videos(str(input_path), args.output)

        print(f"\n{'='*60}")
        print(f"✅ Done! Processed {len(results)} file(s)")
        total_chunks = sum(len(chunks) for chunks in results.values())
        print(f"   Total chunks created: {total_chunks}")
        print(f"   All files encoded with Opus audio for Snowflake/Gemini compatibility")
    else:
        print(f"Error: '{args.input}' is not a valid file or directory")
        exit(1)
