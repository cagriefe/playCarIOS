#!/usr/bin/env python3
"""Generate and sign the "PlayCar DND" shortcut bundled with the app.

The shortcut receives text input "on" / "off" and turns Do Not Disturb on or
off (iOS does not let apps change Focus directly). PlayCar runs it through
shortcuts://x-callback-url and gets control back via playcar://dnd/...

Usage (macOS, signed in to iCloud):
    python3 tools/make-dnd-shortcut.py

Signed shortcuts embed an Apple certificate that expires after roughly a
year; re-run this script to refresh PlayCarIOS/Resources/PlayCar DND.shortcut.
"""
import os
import plistlib
import subprocess
import tempfile
import uuid

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT = os.path.join(ROOT, "PlayCarIOS", "Resources", "PlayCar DND.shortcut")

FOCUS = {"DisplayString": "Do Not Disturb", "Identifier": "com.apple.donotdisturb.mode.default"}
SHORTCUT_INPUT = {
    "Type": "Variable",
    "Variable": {"Value": {"Type": "ExtensionInput"}, "WFSerializationType": "WFTextTokenAttachment"},
}


def build() -> dict:
    group = str(uuid.uuid4()).upper()
    return {
        "WFWorkflowActions": [
            # If Shortcut Input is "on"
            {"WFWorkflowActionIdentifier": "is.workflow.actions.conditional",
             "WFWorkflowActionParameters": {"GroupingIdentifier": group, "WFControlFlowMode": 0,
                                            "WFCondition": 4, "WFConditionalActionString": "on",
                                            "WFInput": SHORTCUT_INPUT}},
            #   Turn Do Not Disturb on until turned off
            {"WFWorkflowActionIdentifier": "is.workflow.actions.dnd.set",
             "WFWorkflowActionParameters": {"Enabled": 1, "FocusModes": FOCUS, "AssertionType": "Turned Off"}},
            # Otherwise
            {"WFWorkflowActionIdentifier": "is.workflow.actions.conditional",
             "WFWorkflowActionParameters": {"GroupingIdentifier": group, "WFControlFlowMode": 1}},
            #   Turn Do Not Disturb off
            {"WFWorkflowActionIdentifier": "is.workflow.actions.dnd.set",
             "WFWorkflowActionParameters": {"Enabled": 0, "FocusModes": FOCUS}},
            # End If
            {"WFWorkflowActionIdentifier": "is.workflow.actions.conditional",
             "WFWorkflowActionParameters": {"GroupingIdentifier": group, "WFControlFlowMode": 2,
                                            "UUID": str(uuid.uuid4()).upper()}},
        ],
        "WFWorkflowClientVersion": "5037.0.17",
        "WFWorkflowMinimumClientVersion": 900,
        "WFWorkflowMinimumClientVersionString": "900",
        "WFWorkflowIcon": {"WFWorkflowIconStartColor": 1440408063, "WFWorkflowIconGlyphNumber": 59511},
        "WFWorkflowImportQuestions": [],
        "WFWorkflowInputContentItemClasses": ["WFStringContentItem"],
        "WFWorkflowOutputContentItemClasses": [],
        "WFWorkflowTypes": [],
        "WFQuickActionSurfaces": [],
        "WFWorkflowHasShortcutInputVariables": True,
        "WFWorkflowHasOutputFallback": False,
    }


def main() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        unsigned = os.path.join(tmp, "PlayCar DND.unsigned.shortcut")
        with open(unsigned, "wb") as f:
            plistlib.dump(build(), f, fmt=plistlib.FMT_BINARY)
        subprocess.run(["shortcuts", "sign", "--mode", "anyone", "--input", unsigned, "--output", OUTPUT], check=True)
    print(f"Signed shortcut written to {OUTPUT}")


if __name__ == "__main__":
    main()
