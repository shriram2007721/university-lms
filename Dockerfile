FROM nginx:alpine
COPY index.html /usr/share/nginx/html/index.html
COPY healthz.html /usr/share/nginx/html/healthz.html
EXPOSE 80
