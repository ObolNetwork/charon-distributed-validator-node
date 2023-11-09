# Server Resource Monitoring Script with Telegram Notifications

## Description
This script monitors server resources such as network usage, disk space, memory utilization, and CPU usage, and sends this information to a specified Telegram chat at regular intervals.

## Installation
Before running the script, ensure you have the necessary utilities and Python libraries installed:

```bash
# Ensure pip is installed
sudo apt update
sudo apt install screen python3-pip -y
pip3 install psutil
pip3 install pyTelegramBotAPI

# Run command 
screen
python3 fast_check.py
```

## Configuration
Make sure to update the following variables in the script:
- YOUR_TELEGRAM_BOT_TOKEN: Your Telegram bot token obtained from BotFather.
- YOUR_CHAT_ID: Your Telegram chat ID.

## Customization
You can customize the script by adjusting the monitoring intervals, adding additional resource checks, or modifying the Telegram message format according to your specific requirements.
