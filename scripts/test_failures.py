#!/usr/bin/env python3
"""Print the failure messages of the latest test run.

xcodebuild -quiet shows which Swift Testing tests failed but not why; the messages
("Expectation failed: (a → 1) == (b → 2)") are only in the .xcresult bundle.
"""
import glob
import json
import os
import subprocess
import sys

bundles = sorted(glob.glob("build/DerivedData/Logs/Test/*.xcresult"), key=os.path.getmtime)
if not bundles:
    sys.exit("No test results in build/DerivedData/Logs/Test.")
path = bundles[-1]


def xcresult(*args):
    out = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", *args, "--path", path],
                         capture_output=True, text=True, check=True).stdout
    return json.loads(out)


def failed_ids(node):
    if node.get("nodeType") == "Test Case" and node.get("result") == "Failed":
        yield node["nodeIdentifier"]
    for child in node.get("children", []):
        yield from failed_ids(child)


def messages(node):
    name = node.get("name", "")
    if node.get("nodeType") == "Failure Message" or name.startswith(("Expectation failed", "Caught error", "Issue recorded")):
        yield name
    for child in node.get("children", []):
        yield from messages(child)


for root in xcresult("tests")["testNodes"]:
    for test_id in dict.fromkeys(failed_ids(root)):
        print(f"✗ {test_id}")
        details = xcresult("test-details", "--test-id", test_id)
        for run in details.get("testRuns", []):
            for message in dict.fromkeys(messages(run)):
                print(f"    {message}")
