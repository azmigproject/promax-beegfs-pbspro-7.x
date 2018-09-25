echo "start" >> /root/NISlog.txt
service NetworkManager stop
systemctl restart ypbind 
service NetworkManager start
echo "stop" >> /root/NISlog.txt