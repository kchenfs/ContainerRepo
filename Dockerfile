# Use an official Nginx runtime as a parent image
FROM nginx

# Set the working directory to /usr/share/nginx/html
WORKDIR /usr/share/nginx/html

# Copy the ZIP file into the container
COPY WebsiteTemplate /usr/share/nginx/html/

# Expose port 80 for the web server
EXPOSE 8081

