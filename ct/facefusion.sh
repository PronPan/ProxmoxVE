#!/usr/bin/env bash
# Ensure build.func is sourced from your fork
source <(curl -fsSL https://raw.githubusercontent.com/PronPan/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 tteck, PronPan
# Author: tteck (tteckster), PronPan
# License: MIT
# Source: https://github.com/facefusion/facefusion

APP="FaceFusion"
var_tags="${var_tags:-ai,graphics}" # Suggest relevant tags
var_cpu="${var_cpu:-2}"             # Minimum 2 cores recommended
var_ram="${var_ram:-4096}"          # Minimum 4GB RAM recommended
var_disk="${var_disk:-32}"          # Increased disk for models/conda env
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}" # Should work unprivileged

# Call functions from build.func
header_info "$APP"
variables # Sets NSAPP based on APP
color
catch_errors

# Main execution flow from build.func
start # Handles user interaction (install/update check) -> install_script
build_container # Creates LXC and runs facefusion-install.sh inside
description # Sets the description in Proxmox

# Completion Message
msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Note: The service is enabled but not started.${CL}"
echo -e "${INFO}${YW} Start it manually via the Proxmox console: 'pct enter ${CTID}' then 'systemctl start facefusion'${CL}"
# FaceFusion runs a web UI, but the default port isn't fixed/obvious from install docs
# We might need to add instructions on how to find the port or configure it later.
echo -e "${INFO}${YW} Access FaceFusion via its web interface (Port may vary, check FaceFusion logs/docs)${CL}"
