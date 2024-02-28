#! /bin/bash
sudo chown root /opt/csye6225/webapp/
sudo chown root /opt/csye6225/webapp/.env

cd /opt/csye6225/webapp/

echo "" | sudo tee /opt/csye6225/webapp/.env
echo "DB_NAME=${dbName}" | sudo tee -a /opt/csye6225/webapp/.env
echo "DB_USER=${sqlUser}" | sudo tee -a /opt/csye6225/webapp/.env
echo "DB_PASSWORD=${password}" | sudo tee -a /opt/csye6225/webapp/.env
echo "DB_HOST=${host}" | sudo tee -a /opt/csye6225/webapp/.env

sudo chown csye6225 /opt/csye6225/webapp/
sudo chown csye6225 /opt/csye6225/webapp/.env

sudo systemctl daemon-reload
sudo systemctl restart WebappService