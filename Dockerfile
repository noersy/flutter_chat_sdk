# ============================================
# Stage 1: Build Flutter Web
# ============================================
FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /app

# Copy the entire project (SDK + example)
COPY . .

# Get dependencies for the SDK package
RUN flutter pub get

# Get dependencies for the example app
WORKDIR /app/example
RUN flutter pub get

# Build Flutter web in release mode
RUN flutter build web --release

# ============================================
# Stage 2: Serve with Nginx
# ============================================
FROM nginx:alpine

# Remove default nginx config
RUN rm /etc/nginx/conf.d/default.conf

# Copy custom nginx config
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copy built Flutter web app from build stage
COPY --from=build /app/example/build/web /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
