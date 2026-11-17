#!/usr/bin/env python3
"""v1 (JAR) APK signing that Android 4.2 accepts: SHA-1 digests, SHA1withRSA certificate and a
PKCS#7 signature block WITHOUT signed attributes (like AOSP's original signapk). Uses the openssl CLI.

usage: sign_apk.py UNSIGNED.apk OUT.apk KEY.pem CERT.pem
"""
import base64
import hashlib
import os
import subprocess
import sys
import tempfile
import zipfile


def b64sha1(data):
    return base64.b64encode(hashlib.sha1(data).digest()).decode()


def main(src, dst, key, cert):
    with zipfile.ZipFile(src) as z:
        entries = [(i.filename, z.read(i.filename)) for i in z.infolist() if not i.filename.startswith("META-INF/")]

    mf_main = "Manifest-Version: 1.0\r\nCreated-By: w200 sign_apk.py\r\n\r\n"
    sections = []
    for name, data in entries:
        sections.append((name, f"Name: {name}\r\nSHA1-Digest: {b64sha1(data)}\r\n\r\n"))
    mf = mf_main + "".join(s for _, s in sections)

    sf = ("Signature-Version: 1.0\r\nCreated-By: w200 sign_apk.py\r\n"
          f"SHA1-Digest-Manifest: {b64sha1(mf.encode())}\r\n\r\n")
    for name, sec in sections:
        sf += f"Name: {name}\r\nSHA1-Digest: {b64sha1(sec.encode())}\r\n\r\n"

    with tempfile.TemporaryDirectory() as td:
        sf_path, rsa_path = os.path.join(td, "CERT.SF"), os.path.join(td, "CERT.RSA")
        with open(sf_path, "wb") as f:
            f.write(sf.encode())
        subprocess.run(["openssl", "smime", "-sign", "-binary", "-noattr", "-md", "sha1",
                        "-in", sf_path, "-signer", cert, "-inkey", key, "-outform", "DER", "-out", rsa_path],
                       check=True)
        rsa = open(rsa_path, "rb").read()

    with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("META-INF/MANIFEST.MF", mf)
        z.writestr("META-INF/CERT.SF", sf)
        z.writestr("META-INF/CERT.RSA", rsa)
        for name, data in entries:
            z.writestr(name, data)


if __name__ == "__main__":
    main(*sys.argv[1:5])
