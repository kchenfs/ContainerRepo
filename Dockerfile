# Use an official Nginx runtime as a parent image
FROM nginx

# Set the working directory to /usr/share/nginx/html
WORKDIR /usr/share/nginx/html

# Copy the contents of the "FrontEnd" folder from your Git repository
COPY FrontEnd/ /usr/share/nginx/html/

# Expose port 80 for the web server
EXPOSE 80
