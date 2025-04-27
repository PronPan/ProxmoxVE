#!/usr/bin/env bash
# This script is executed inside the LXC by build_container

# Copyright (c) 2021-2025 tteck, PronPan
# Author: tteck (tteckster), PronPan
# License: MIT
# Source: https://github.com/facefusion/facefusion

# Source common functions (path provided by build.func)
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Prerequisites (git, curl, ffmpeg)"
$STD apt-get update
$STD apt-get -y install \
    git \
    curl \
    ffmpeg
msg_ok "Installed Prerequisites"

msg_info "Installing Miniconda"
# Use /opt for conda installation within container
CONDA_INSTALL_PATH="/opt/miniconda3"
curl -LO https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
# Run installer non-interactively, accepting license, installing to specified path
bash Miniconda3-latest-Linux-x86_64.sh -b -p "$CONDA_INSTALL_PATH"
rm Miniconda3-latest-Linux-x86_64.sh
# Initialize conda for bash environment (needed for subsequent conda commands)
"$CONDA_INSTALL_PATH/bin/conda" init bash
# Source the conda bash functions for the current script execution
source "$CONDA_INSTALL_PATH/etc/profile.d/conda.sh"
msg_ok "Installed Miniconda"

msg_info "Creating and Activating Conda Environment 'facefusion'"
# Create the environment
conda create --name facefusion python=3.12 -y
# Activate - needed if subsequent commands directly use 'python'/'pip' without full path
conda activate facefusion
msg_ok "Created and Activated Conda Environment 'facefusion'"

msg_info "Cloning FaceFusion Repository"
# Clone into /opt for consistency
FACEFUSION_APP_PATH="/opt/facefusion"
git clone https://github.com/facefusion/facefusion "$FACEFUSION_APP_PATH"
cd "$FACEFUSION_APP_PATH"
msg_ok "Cloned FaceFusion Repository to $FACEFUSION_APP_PATH"

msg_info "Installing FaceFusion Application Dependencies"
# Use the python executable from the specific conda environment for robustness
"$CONDA_INSTALL_PATH/envs/facefusion/bin/python" install.py --onnxruntime default --skip-conda
msg_ok "Installed FaceFusion Application Dependencies"

# Deactivate environment (good practice in script)
conda deactivate

msg_info "Creating FaceFusion Systemd Service"
cat <<EOF >/etc/systemd/system/facefusion.service
[Unit]
Description=FaceFusion Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${FACEFUSION_APP_PATH}
ExecStart=${CONDA_INSTALL_PATH}/envs/facefusion/bin/python run.py
Restart=always
# Add environment variables if needed, e.g. for specific ports or models
# Environment="VAR=value"

[Install]
WantedBy=multi-user.target
EOF
msg_ok "Created Systemd Service File"

msg_info "Enabling FaceFusion Service (Will not start automatically)"
systemctl enable facefusion.service
msg_ok "Enabled FaceFusion Service"

# Call final customization functions from sourced file
motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
