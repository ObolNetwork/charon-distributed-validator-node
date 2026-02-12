import psutil
import socket
import time
import telebot

def get_gb(size_bytes):
    gb = size_bytes / (1024 ** 3)
    return "{:.2f} GB".format(gb)

def get_ip():
    try:
        host_name = socket.gethostname()
        host_ip = socket.gethostbyname(host_name)
        return host_name, host_ip
    except:
        return "Unknown", "Unknown"

def get_memory_info():
    memory_info = psutil.virtual_memory()
    total_memory = get_gb(memory_info.total)
    used_memory = memory_info.percent
    return f"{used_memory}% ({total_memory})"


#  'YOUR_TELEGRAM_BOT_TOKEN' from  BotFather
bot = telebot.TeleBot('')
chat_id = ''  # NUMBER CHAT_ID

while True:
    # TOTAL INFO
    network_info = psutil.net_io_counters()
    disk_info = psutil.disk_usage('/')
    memory_info = get_memory_info()
    cpu_info = psutil.cpu_percent(interval=None, percpu=True)

    # NETWORK INFO  MB/s
    sent_speed = network_info.bytes_sent / (1024 ** 2) / 1800  # в MB/s
    recv_speed = network_info.bytes_recv / (1024 ** 2) / 1800  # в MB/s

    # DISK INFO
    disk_free_gb = get_gb(disk_info.free)
    disk_free_percent = disk_info.percent

    # CPU INFO
    cpu_count = psutil.cpu_count()
    cpu_percent = sum(psutil.cpu_percent(interval=None, percpu=True)) / cpu_count

    # RAM INFO
    memory_percent = memory_info

    # Hostname и IP
    hostname, ip = get_ip()

    # Send Telegram
    message = f"Hostname😊: {hostname}\nIP: {ip}\n\n"
    message += f"Network usage 📡: \nSent: {sent_speed:.2f} MB/s\nReceived: {recv_speed:.2f} MB/s\n\n"
    message += f"Free Spase 💾: {disk_free_gb} ({disk_free_percent}% Busy)\n\n"
    message += f"Memory Usage 💭: {memory_percent}\n\n"
    message += f"Cpu Usage 🧠: \nTotal: {cpu_count}\nConsumption: {cpu_percent}%"

    # Check every 30 min (sec)
    bot.send_message(chat_id, message)
    time.sleep(1800)
