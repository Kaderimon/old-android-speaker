#!/usr/bin/env python3
"""Write AndroidManifest.xml in Android's binary XML format (no aapt / Android SDK needed).

Only what a resource-less APK needs: string pool, resource-ID map for the android: attributes,
namespace and element chunks. Attributes with resource IDs are sorted by ID inside each element,
because Android's attribute lookup walks them in ID order.
"""
import struct
import sys

NS = "http://schemas.android.com/apk/res/android"

# android:attribute -> framework resource id
ATTR_IDS = {
    "theme": 0x01010000, "label": 0x01010001, "icon": 0x01010002, "name": 0x01010003,
    "clearTaskOnLaunch": 0x01010015, "stateNotNeeded": 0x01010016, "excludeFromRecents": 0x01010017,
    "launchMode": 0x0101001d, "screenOrientation": 0x0101001e,
    "minSdkVersion": 0x0101020c, "versionCode": 0x0101021b, "versionName": 0x0101021c,
    "targetSdkVersion": 0x01010270,
}
T_REF, T_STRING, T_INT_DEC, T_BOOL = 0x01, 0x03, 0x10, 0x12

PKG = "com.w200.nowplaying"
TREE = ("manifest", [("package", None, PKG), ("versionCode", T_INT_DEC, 1), ("versionName", T_STRING, "1.0")], [
    ("uses-sdk", [("minSdkVersion", T_INT_DEC, 16), ("targetSdkVersion", T_INT_DEC, 17)], []),
    ("uses-permission", [("name", T_STRING, "android.permission.INTERNET")], []),
    ("application", [("label", T_STRING, "W200"),
                     ("theme", T_REF, 0x0103000a)],        # @android:style/Theme.NoTitleBar.Fullscreen
     [("activity", [("name", T_STRING, PKG + ".NowPlaying"), ("label", T_STRING, "W200"),
                    ("launchMode", T_INT_DEC, 2),           # singleTask
                    ("screenOrientation", T_INT_DEC, 1),    # portrait
                    ("stateNotNeeded", T_BOOL, True), ("clearTaskOnLaunch", T_BOOL, True),
                    ("excludeFromRecents", T_BOOL, True)],
       [("intent-filter", [], [
           ("action", [("name", T_STRING, "android.intent.action.MAIN")], []),
           ("category", [("name", T_STRING, "android.intent.category.HOME")], []),
           ("category", [("name", T_STRING, "android.intent.category.DEFAULT")], []),
           ("category", [("name", T_STRING, "android.intent.category.LAUNCHER")], []),
       ])])]),
])


def main(out):
    # --- string pool: android attribute names first (aligned with the resource map), then the rest
    attr_names, others = [], []
    def walk(node):
        tag, attrs, kids = node
        others.append(tag)
        for name, typ, val in attrs:
            if name in ATTR_IDS:
                if name not in attr_names: attr_names.append(name)
            else:
                others.append(name)
            if typ == T_STRING or typ is None: others.append(val)
        for k in kids: walk(k)
    walk(TREE)
    attr_names.sort(key=lambda n: ATTR_IDS[n])
    strings = list(attr_names)
    for s in ["android", NS] + others:
        if s not in strings: strings.append(s)
    idx = {s: i for i, s in enumerate(strings)}

    def string_pool():
        offs, data = [], b""
        for s in strings:
            offs.append(len(data))
            u = s.encode("utf-16-le")
            data += struct.pack("<H", len(s)) + u + b"\0\0"
        while len(data) % 4: data += b"\0"
        hdr_size = 28
        strings_start = hdr_size + 4 * len(strings)
        body = b"".join(struct.pack("<I", o) for o in offs) + data
        return struct.pack("<HHIIIIII", 0x0001, hdr_size, hdr_size + len(body), len(strings), 0, 0, strings_start, 0) + body

    def res_map():
        body = b"".join(struct.pack("<I", ATTR_IDS[n]) for n in attr_names)
        return struct.pack("<HHI", 0x0180, 8, 8 + len(body)) + body

    chunks = []
    line = [1]
    def node_chunk(ctype, ext):
        line[0] += 1
        return struct.pack("<HHIIi", ctype, 16, 16 + len(ext), line[0], -1) + ext

    def emit(node):
        tag, attrs, kids = node
        plain = [a for a in attrs if a[0] not in ATTR_IDS]
        android = sorted([a for a in attrs if a[0] in ATTR_IDS], key=lambda a: ATTR_IDS[a[0]])
        ab = b""
        for name, typ, val in plain + android:
            ns = idx[NS] if name in ATTR_IDS else 0xFFFFFFFF
            if typ is None or typ == T_STRING:
                raw, dtype, data = idx[val], T_STRING, idx[val]
            elif typ == T_BOOL:
                raw, dtype, data = 0xFFFFFFFF, T_BOOL, 0xFFFFFFFF if val else 0
            else:
                raw, dtype, data = 0xFFFFFFFF, typ, val
            ab += struct.pack("<IIIHBBI", ns, idx[name], raw, 8, 0, dtype, data)
        n = len(plain) + len(android)
        ext = struct.pack("<IIHHHHHH", 0xFFFFFFFF, idx[tag], 20, 20, n, 0, 0, 0) + ab
        chunks.append(node_chunk(0x0102, ext))
        for k in kids: emit(k)
        chunks.append(node_chunk(0x0103, struct.pack("<II", 0xFFFFFFFF, idx[tag])))

    ns_ext = struct.pack("<II", idx["android"], idx[NS])
    chunks.append(node_chunk(0x0100, ns_ext))
    emit(TREE)
    chunks.append(node_chunk(0x0101, ns_ext))

    body = string_pool() + res_map() + b"".join(chunks)
    with open(out, "wb") as f:
        f.write(struct.pack("<HHI", 0x0003, 8, 8 + len(body)) + body)


if __name__ == "__main__":
    main(sys.argv[1])
