# RDS database tier

Amazon RDS MySQL runs in private DB subnets. There is no database-server EC2 to configure.

## Required RDS configuration

- Disable public access.
- Allow inbound TCP `3306` only from the application EC2 security group.
- Enable encryption at rest, automated backups, and deletion protection.
- Enable Multi-AZ for production availability.
- Keep the RDS master login for provisioning only. Flask uses the limited `spxapp` MySQL user created by the application setup script.

## Database objects created by the application setup script

- Database/schema: `spxbank`
- Application MySQL user: `spxapp`
- TLS CA bundle on the application EC2: `/etc/ssl/certs/rds-global-bundle.pem`

## Safe verification from the application EC2

The following command reads the protected application environment file without printing the password. It lists tables and displays the negotiated TLS cipher.

```bash
sudo bash -c '
  set -a
  . /etc/spx-banking.env
  MYSQL_PWD="$DB_PASS" mysql \
    --host="$DB_HOST" \
    --port="$DB_PORT" \
    --user="$DB_USER" \
    --ssl-ca="$DB_SSL_CA" \
    "$DB_NAME" \
    -e "SHOW TABLES; SHOW STATUS LIKE \"Ssl_cipher\";"
'
```

The expected result includes the SPX tables and a non-empty `Ssl_cipher` value.

