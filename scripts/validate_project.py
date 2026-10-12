"""Validate project wiring without requiring Xcode (does not compile Swift)."""
import json
import plistlib
import re
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def parse_openstep(source):
    source = re.sub(r"/\*.*?\*/|//[^\n]*", "", source, flags=re.S)
    tokens = re.findall(r'"(?:\\.|[^"\\])*"|[{}()=;,]|[^\s{}()=;,]+', source)
    offset = 0

    def take(expected=None):
        nonlocal offset
        token = tokens[offset]
        offset += 1
        if expected is not None and token != expected:
            raise ValueError(f"Expected {expected!r}, received {token!r}")
        return token

    def value():
        token = take()
        if token == "{":
            result = {}
            while tokens[offset] != "}":
                key = take()
                if key.startswith('"'):
                    key = json.loads(key)
                if key in result:
                    raise ValueError(f"Duplicate key: {key}")
                take("=")
                result[key] = value()
                take(";")
            take("}")
            return result
        if token == "(":
            result = []
            while tokens[offset] != ")":
                result.append(value())
                if tokens[offset] == ",":
                    take(",")
                elif tokens[offset] != ")":
                    raise ValueError("Missing array separator")
            take(")")
            return result
        return json.loads(token) if token.startswith('"') else token

    result = value()
    if offset != len(tokens):
        raise ValueError("Unexpected trailing tokens")
    return result


project = parse_openstep((ROOT / "InkArchive.xcodeproj/project.pbxproj").read_text(encoding="utf-8"))
objects = project["objects"]
assert objects[project["rootObject"]]["isa"] == "PBXProject"


def check_references(value):
    if isinstance(value, dict):
        for item in value.values():
            check_references(item)
    elif isinstance(value, list):
        for item in value:
            check_references(item)
    elif re.fullmatch(r"A[0-9A-F]{23}", value):
        assert value in objects, f"Missing project object: {value}"


check_references(objects)
refs = {key: obj for key, obj in objects.items() if obj["isa"] == "PBXFileReference"}
source_ids = set()
for obj in objects.values():
    if obj["isa"] == "PBXSourcesBuildPhase":
        source_ids.update(objects[build]["fileRef"] for build in obj["files"])
source_names = {refs[key]["path"] for key in source_ids}
actual_names = {path.name for path in (ROOT / "InkArchiveApp").glob("*.swift")}
assert source_names == actual_names, "Swift sources missing from the App target"
for name in source_names:
    assert (ROOT / "InkArchiveApp" / name).is_file()
assert (ROOT / "InkArchiveCore/Package.swift").is_file()
info = plistlib.loads((ROOT / "InkArchiveApp/Info.plist").read_bytes())
assert info["NSCameraUsageDescription"]
assert info["UISupportedInterfaceOrientations"] == ["UIInterfaceOrientationPortrait"]
scheme = ET.parse(ROOT / "InkArchive.xcodeproj/xcshareddata/xcschemes/InkArchive.xcscheme")
for ref in scheme.iter("BuildableReference"):
    assert objects[ref.attrib["BlueprintIdentifier"]]["isa"] == "PBXNativeTarget"
print(f"PASS: project references, {len(source_names)} App sources, camera plist, shared scheme")
