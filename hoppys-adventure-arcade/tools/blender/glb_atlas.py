"""Pure Python glTF atlas sharing and PNG census, also usable without Blender."""
import hashlib
import json
import struct


def inspect_images(payload, binary):
    result = []
    for index, image in enumerate(payload.get('images', [])):
        view = payload['bufferViews'][image['bufferView']]
        start = view.get('byteOffset', 0)
        raw = binary[start:start + view['byteLength']]
        if raw[:8] != b'\x89PNG\r\n\x1a\n':
            raise RuntimeError('[hoppy] Expected embedded PNG: ' + str(image))
        width, height = struct.unpack_from('>II', raw, 16)
        result.append({'index': index, 'name': image.get('name', ''),
                       'width': width, 'height': height, 'bytes': len(raw),
                       'sha256': hashlib.sha256(raw).hexdigest()})
    return result


def consolidate_atlases(payload, binary):
    """Share identical image/texture records; keep existing binary offsets intact."""
    image_remap, unique_images, seen = {}, [], {}
    for info in inspect_images(payload, binary):
        key = info['sha256']
        if key not in seen:
            seen[key] = len(unique_images)
            unique_images.append(payload['images'][info['index']])
        image_remap[info['index']] = seen[key]
    payload['images'] = unique_images
    texture_remap, unique_textures, seen = {}, [], {}
    for index, texture in enumerate(payload.get('textures', [])):
        texture['source'] = image_remap[texture['source']]
        key = json.dumps(texture, sort_keys=True)
        if key not in seen:
            seen[key] = len(unique_textures)
            unique_textures.append(texture)
        texture_remap[index] = seen[key]
    payload['textures'] = unique_textures

    def remap(value):
        if isinstance(value, dict):
            for key, child in value.items():
                if key.endswith('Texture') and isinstance(child, dict) and 'index' in child:
                    child['index'] = texture_remap[child['index']]
                else:
                    remap(child)
        elif isinstance(value, list):
            for child in value:
                remap(child)
    remap(payload.get('materials', []))
    for material in payload.get('materials', []):
        mr = material.get('pbrMetallicRoughness', {}).get('metallicRoughnessTexture')
        if mr is not None:
            source = payload['textures'][mr['index']]['source']
            if not payload['images'][source].get('name', '').endswith('_orm'):
                raise RuntimeError('[hoppy] Expected shared ORM atlas: ' + material.get('name', ''))
            # R is baked occlusion (seam and tread grooves; 1 elsewhere), G roughness, B metal.
            material['occlusionTexture'] = dict(mr, strength=1.0)
    return inspect_images(payload, binary)
