"""Render app and Live Activity extension signing options."""
import os
from pathlib import Path
import plistlib
import sys

data = plistlib.loads(Path(__file__).with_name("ExportOptions.plist").read_bytes())
app_id = os.environ.get("APP_ID", "com.hgsldswk.waterout")
data["teamID"] = os.environ["TEAM_ID"]
data["provisioningProfiles"] = {
    app_id: os.environ.get("APP_PROFILE", "WaterOut AppStore"),
    f"{app_id}.widget": os.environ.get("WIDGET_PROFILE", "WaterOut Widget AppStore"),
}
sys.stdout.buffer.write(plistlib.dumps(data))
