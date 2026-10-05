#!/usr/bin/env python3
"""
Minecraft World & Playerdata Inspector
Reads level.dat and playerdata/*.dat files without any external libraries.
"""

import os
import sys
import gzip
import struct

def parse_nbt_tag(stream, tag_type):
    if tag_type == 0: # TAG_End
        return None
    elif tag_type == 1: # TAG_Byte
        return struct.unpack('>b', stream.read(1))[0]
    elif tag_type == 2: # TAG_Short
        return struct.unpack('>h', stream.read(2))[0]
    elif tag_type == 3: # TAG_Int
        return struct.unpack('>i', stream.read(4))[0]
    elif tag_type == 4: # TAG_Long
        return struct.unpack('>q', stream.read(8))[0]
    elif tag_type == 5: # TAG_Float
        return struct.unpack('>f', stream.read(4))[0]
    elif tag_type == 6: # TAG_Double
        return struct.unpack('>d', stream.read(8))[0]
    elif tag_type == 7: # TAG_Byte_Array
        length = struct.unpack('>i', stream.read(4))[0]
        return stream.read(length)
    elif tag_type == 8: # TAG_String
        length = struct.unpack('>H', stream.read(2))[0]
        return stream.read(length).decode('utf-8', errors='replace')
    elif tag_type == 9: # TAG_List
        sub_type = stream.read(1)[0]
        length = struct.unpack('>i', stream.read(4))[0]
        return [parse_nbt_tag(stream, sub_type) for _ in range(length)]
    elif tag_type == 10: # TAG_Compound
        compound = {}
        while True:
            sub_type = stream.read(1)
            if not sub_type or sub_type[0] == 0:
                break
            name_len = struct.unpack('>H', stream.read(2))[0]
            name = stream.read(name_len).decode('utf-8', errors='replace')
            compound[name] = parse_nbt_tag(stream, sub_type[0])
        return compound
    elif tag_type == 11: # TAG_Int_Array
        length = struct.unpack('>i', stream.read(4))[0]
        return [struct.unpack('>i', stream.read(4))[0] for _ in range(length)]
    elif tag_type == 12: # TAG_Long_Array
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
            
    stream = io.BytesIO(data) if 'io' in globals() else None
    import io
    stream = io.BytesIO(data)
    root_type = stream.read(1)[0]
    if root_type == 0:
        return {}
    name_len = struct.unpack('>H', stream.read(2))[0]
    name = stream.read(name_len).decode('utf-8', errors='replace')
    return parse_nbt_tag(stream, root_type)

def inspect_world(world_dir):
    print("=" * 70)
    print(f"  MINECRAFT WORLD INSPECTOR: {world_dir}")
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
        print("[!] No level.dat found in this folder.")
        
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
                
                item_names = [item.get("id", "item") for item in inv[:5]]
                if len(inv) > 5:
                    item_names.append(f"... +{len(inv)-5} more")
                    
                print(f"\n    👤 Player UUID: {f.replace('.dat', '')}")
                print(f"       Position:     X={pos[0]:.1f}, Y={pos[1]:.1f}, Z={pos[2]:.1f} ({dim})")
                print(f"       Health:       {hp}/20 | XP Level: {xp}")
                print(f"       Items count:  {len(inv)} items")
                if item_names:
                    print(f"       Sample Items: {', '.join(item_names)}")
            except Exception as e:
                print(f"    [!] Error reading {f}: {e}")
    else:
        print("\n[!] No playerdata folder found.")
    print("\n" + "=" * 70)

if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else "world"
    if not os.path.exists(target):
        target = os.path.join(os.path.dirname(__file__), "world")
    inspect_world(target)
