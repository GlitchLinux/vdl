#!/bin/bash

sudo apt update && sudo apt install python3-requests python3-bs4 python3-lxml -y
cd /tmp && wget https://raw.githubusercontent.com/GlitchLinux/vdl/refs/heads/main/url-lister.py
python3 url-lister.py
