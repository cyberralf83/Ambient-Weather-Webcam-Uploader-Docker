# Ambient Weather Webcam Uploader - Docker

A robust Docker container that automatically downloads snapshots from your IP webcam and uploads them to Ambient Weather's FTP server at configurable intervals.

## Features

- Automated snapshot capture and upload on a configurable schedule
- Retry logic for both download and upload operations
- Image validation to ensure valid snapshots are uploaded
- Timestamped logging for easy troubleshooting
- Automatic cleanup of old archived images
- Docker health checks for monitoring container status
- Configurable timeouts and retry attempts
- Timezone support
- Persistent storage for logs and archived images

## Quick Start

### Prerequisites

- Docker and Docker Compose installed
- An IP camera accessible via HTTP/HTTPS
- Ambient Weather account credentials

### Basic Setup

1. Clone this repository:
   ```bash
   git clone <repository-url>
   cd Ambient-Weather-Webcam-Uploader-Docker
   ```

2. Create a `.env` file with your configuration:
   ```bash
   cp .env.example .env
   ```

3. Edit `.env` with your settings:
   ```env
   # Required settings
   INPUT_IP=http://192.168.1.100/snapshot.jpg
   USERNAME=your_ambient_weather_username
   PASSWORD=your_ambient_weather_password
   ```

4. Build and run the container:
   ```bash
   docker-compose up -d
   ```

5. Check the logs:
   ```bash
   docker-compose logs -f
   ```

## Configuration

### Required Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `INPUT_IP_ADDRESS` | URL to your webcam snapshot | `http://192.168.1.100/snapshot.jpg` |
| `USERNAME` | Ambient Weather username | `your_username` |
| `PASSWORD` | Ambient Weather password | `your_password` |

### Optional Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SERVER` | `ftp2.ambientweather.net` | FTP server address |
| `PORT` | `21` | FTP server port |
| `CRON_SCHEDULE` | `*/2 * * * *` | Cron schedule (every 2 minutes) |
| `MAX_RETRIES` | `3` | Number of retry attempts |
| `RETRY_DELAY` | `5` | Seconds between retry attempts |
| `TIMEOUT` | `30` | Download/upload timeout in seconds |
| `MIN_IMAGE_SIZE` | `1024` | Minimum valid image size in bytes |
| `KEEP_IMAGES` | `5` | Number of archived images to keep |
| `HEALTHCHECK_MAX_AGE` | `300` | Max age of image for health check (seconds) |
| `TZ` | `UTC` | Timezone (e.g., `America/New_York`) |

### Cron Schedule Examples

- Every 2 minutes (default): `*/2 * * * *`
- Every 5 minutes: `*/5 * * * *`
- Every hour: `0 * * * *`
- Every 30 minutes: `*/30 * * * *`
- Every day at 8 AM: `0 8 * * *`

## Building the Image

```bash
docker build -t ams-cam-upload .
```

## Running with Docker Compose

```bash
# Start the container
docker-compose up -d

# View logs
docker-compose logs -f

# Stop the container
docker-compose down

# Restart the container
docker-compose restart
```

## Running with Docker CLI

```bash
docker run -d \
  --name ams-cam-upload \
  --restart unless-stopped \
  -e INPUT_IP_ADDRESS="http://192.168.1.100/snapshot.jpg" \
  -e USERNAME="your_username" \
  -e PASSWORD="your_password" \
  -e CRON_SCHEDULE="*/2 * * * *" \
  -v ./data/archive:/home/root/archive \
  -v ./data/logs:/var/log \
  ams-cam-upload
```

## Monitoring

### Health Check

The container includes a built-in health check that monitors:
- Whether the cron daemon is running
- Age of the last downloaded image
- Recent error patterns in logs

Check container health:
```bash
docker ps
docker inspect --format='{{.State.Health.Status}}' ams-cam-upload
```

### Viewing Logs

```bash
# Docker Compose
docker-compose logs -f

# Docker CLI
docker logs -f ams-cam-upload

# View logs from mounted volume
tail -f ./data/logs/ams-cam-upload.log
```

### Archived Images

Uploaded images are automatically archived with timestamps in `/home/root/archive` inside the container. When using the provided docker-compose configuration, these are persisted to `./data/archive` on your host.

## Troubleshooting

### Common Issues

1. **Container not starting**
   - Check logs: `docker-compose logs`
   - Verify environment variables are set correctly
   - Ensure webcam URL is accessible

2. **Images not uploading**
   - Verify Ambient Weather credentials
   - Check FTP server is accessible
   - Review logs for error messages
   - Verify image downloads are successful

3. **Download failures**
   - Verify webcam URL is correct and accessible
   - Check if webcam requires authentication
   - Increase `TIMEOUT` value for slow networks

4. **Upload failures**
   - Verify FTP credentials
   - Check firewall/network settings
   - Increase `MAX_RETRIES` value

### Debug Mode

To see detailed execution:
```bash
docker-compose logs -f
```

### Manual Testing

Run the upload script manually inside the container:
```bash
docker exec -it ams-cam-upload /usr/local/bin/ams-cam-upload.sh
```

## Advanced Configuration

### Custom Webcam Authentication

If your webcam requires custom headers or cookies, modify `ams-cam-upload.sh:37-39` to add additional wget options:

```bash
if wget "$INPUT_IP_ADDRESS" \
    --header 'Cookie: allow-download=1' \
    --header 'Authorization: Basic YOUR_AUTH' \
    ...
```

### Persistent Storage

The docker-compose configuration includes volumes for:
- **Archived images**: `./data/archive`
- **Logs**: `./data/logs`

These directories will be created automatically on first run.

## Security Considerations

- Store credentials in a `.env` file (add to `.gitignore`)
- Use environment variables, not hardcoded values
- Limit network access to required services only
- Regularly rotate Ambient Weather credentials
- Keep the Docker image updated

## Contributing

Contributions are welcome! Please submit pull requests or open issues for bugs and feature requests.

## License

[Your license here]

## Support

For issues and questions:
- Open an issue on GitHub
- Check existing issues for solutions
- Review logs for error messages

## Changelog

### Version 2.0
- Added error handling and retry logic
- Implemented image validation
- Added configurable cron scheduling
- Implemented health checks
- Added timestamped logging
- Added automatic image archival
- Added disk space management
- Improved documentation

### Version 1.0
- Initial release
- Basic snapshot upload functionality