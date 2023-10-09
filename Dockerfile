# Use an official Nginx runtime as the base image
FROM nginx:latest

# Copy your website files from your local directory to the NGINX document root
COPY ./FrontEnd/* /usr/share/nginx/html/

# Expose port 80 (default for HTTP)
EXPOSE 80

# Start the Nginx web server
CMD ["nginx", "-g", "daemon off;"]
