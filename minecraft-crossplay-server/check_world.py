#!/usr/bin/env python3
"""
Minecraft World & Playerdata Inspector
Auto-detects world folders, level.dat, and playerdata/*.dat files.
"""

import os
import sys
import gzip
import struct
import io

def parse_nbt_tag(stream, tag_type):
    if tag_type == 0:
        return None
    elif tag_type == 1:
        return struct.unpack('>b', stream.read(1))[0]
    elif tag_type == 2:
        return struct.unpack('>h', stream.read(2))[0]
    elif tag_type == 3:
        return struct.unpack('>i', stream.read(4))[0]
    elif tag_type == 4:
        return struct.unpack('>q', stream.read(8))[0]
    elif tag_type == 5:
        return struct.unpack('>f', stream.read(4))[0]
    elif tag_type == 6:
        return struct.unpack('>d', stream.read(8))[0]
    elif tag_type == 7:
        length = struct.unpack('>i', stream.read(4))[0]
        return stream.read(length)
    elif tag_type == 8:
        length = struct.unpack('>H', stream.read(2))[0]
        return stream.read(length).decode('utf-8', errors='replace')
    elif tag_type == 9:
        sub_type = stream.read(1)[0]
        length = struct.unpack('>i', stream.read(4))[0]
        return [parse_nbt_tag(stream, sub_type) for _ in range(length)]
    elif tag_type == 10:
        compound = {}
        while True:
            sub_type = stream.read(1)
            if not sub_type or sub_type[0] == 0:
                break
            name_len = struct.unpack('>H', stream.read(2))[0]
            name = stream.read(name_len).decode('utf-8', errors='replace')
            compound[name] = parse_nbt_tag(stream, sub_type[0])
        return compound
    elif tag_type == 11:
        length = struct.unpack('>i', stream.read(4))[0]
        return [struct.unpack('>i', stream.read(4))[0] for _ in range(length)]
    elif tag_type == 12:
        length = struct.unpack('>i', stream.read(4))[0]
        return [struct.unpack('>q', stream.read(8))[0] for _ in range(length)]
    return None

def load_nbt_file(filepath):
    try:
        with gzip.open(filepath, 'rb') as f:
            data = f.read()
    except Exception:
        with open(filepath, 'rb') as f:
            data = f.read()
            
    stream = io.BytesIO(data)
    root_type = stream.read(1)[0]
    if root_type == 0:
        return {}
    name_len = struct.unpack('>H', stream.read(2))[0]
    name = stream.read(name_len).decode('utf-8', errors='replace')
    return parse_nbt_tag(stream, root_type)

def find_world_roots(start_dir):
    roots = []
    for root, dirs, files in os.walk(start_dir):
        if "level.dat" in files or "playerdata" in dirs or "region" in dirs:
            roots.append(root)
    return roots

def inspect_single_world(world_dir):
    print("=" * 70)
    print(f"  FOUND WORLD AT: {world_dir}")
    print("=" * 70)
    
    level_dat = os.path.join(world_dir, "level.dat")
    if os.path.exists(level_dat):
        try:
            nbt = load_nbt_file(level_dat)
            data = nbt.get("Data", {})
            print(f"[*] World Level Name: {data.get('LevelName', 'Unknown')}")
            print(f"[*] World Seed:       {data.get('WorldGenSettings', {}).get('seed', data.get('RandomSeed', 'Unknown'))}")
            print(f"[*] Game Version:     {data.get('Version', {}).get('Name', 'Unknown')} (ID: {data.get('Version', {}).get('Id', 'Unknown')})")
            print(f"[*] Spawn Point:      X={data.get('SpawnX')}, Y={data.get('SpawnY')}, Z={data.get('SpawnZ')}")
            print(f"[*] Time / Day:       Time: {data.get('DayTime', 0)} (Day ~{data.get('DayTime', 0)//24000})")
        except Exception as e:
            print(f"[!] Error reading level.dat: {e}")
    else:
        print("[!] No level.dat found directly in this subfolder.")
        
    playerdata_dir = os.path.join(world_dir, "playerdata")
    if os.path.exists(playerdata_dir):
        files = [f for f in os.listdir(playerdata_dir) if f.endswith(".dat")]
        print(f"\n[*] Found {len(files)} player data file(s) in playerdata/:")
        for f in files:
            p_path = os.path.join(playerdata_dir, f)
            try:
                p_nbt = load_nbt_file(p_path)
                pos = p_nbt.get("Pos", [0, 0, 0])
                dim = p_nbt.get("Dimension", "minecraft:overworld")
                inv = p_nbt.get("Inventory", [])
                xp = p_nbt.get("XpLevel", 0)
                hp = p_nbt.get("Health", 20)
                
                item_names = [item.get("id", "item") for item in inv[:6]]
                if len(inv) > 6:
                    item_names.append(f"... +{len(inv)-6} more")
                    
                print(f"\n    👤 Player UUID: {f.replace('.dat', '')}")
                print(f"       Position:     X={pos[0]:.1f}, Y={pos[1]:.1f}, Z={pos[2]:.1f} ({dim})")
                print(f"       Health:       {hp}/20 | XP Level: {xp}")
                print(f"       Items count:  {len(inv)} items")
                if item_names:
                    print(f"       Inventory:    {', '.join(item_names)}")
            except Exception as e:
                print(f"    [!] Error reading {f}: {e}")
    else:
        print("\n[!] No playerdata folder in this subfolder.")
        
    region_dir = os.path.join(world_dir, "region")
    if os.path.exists(region_dir):
        mca_files = [f for f in os.listdir(region_dir) if f.endswith(".mca")]
        print(f"\n[*] Overworld Region Files: {len(mca_files)} region (.mca) chunk files")

def main():
    target = sys.argv[1] if len(sys.argv) > 1 else "."
    # If target is specific folder or parent
    search_dir = os.path.dirname(os.path.abspath(target)) if not os.path.isdir(target) else target
    
    # Check parent directory as well
    roots = find_world_roots(search_dir)
    if not roots:
        parent = os.path.dirname(search_dir)
        roots = find_world_roots(parent)
        
    if not roots:
        print("=" * 70)
        print(f"  NO WORLD FILES FOUND IN: {search_dir}")
        print("  Looking for level.dat, playerdata, or region folders...")
        print("=" * 70)
        # List all subfolders to help user
        print("\nFolders found in this location:")
        for item in os.listdir(search_dir):
            full = os.path.join(search_dir, item)
            if os.path.isdir(full):
                print(f"  📁 {item}/")
            else:
                print(f"  📄 {item}")
    else:
        for r in roots:
            inspect_single_world(r)
            print()

if __name__ == "__main__":
    main()
