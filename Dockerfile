# Build stage
FROM hexpm/elixir:1.18.1-erlang-27.2-alpine-3.21.2 AS builder

# Install build dependencies
RUN apk add --no-cache build-base git

# Set working directory
WORKDIR /app

# Install hex and rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Copy mix files
COPY mix.exs mix.lock ./

# Install dependencies
ENV MIX_ENV=prod
RUN mix deps.get --only prod && \
    mix deps.compile

# Copy application code
COPY lib lib

# Compile application
RUN mix compile

# Build release
RUN mix release

# Runtime stage
FROM alpine:3.21.2

# Install runtime dependencies
RUN apk add --no-cache \
    openssl \
    ncurses-libs \
    libstdc++ \
    libgcc

# Create non-root user
RUN addgroup -g 1000 nimbus && \
    adduser -D -u 1000 -G nimbus nimbus

# Set working directory
WORKDIR /app

# Copy release from builder
COPY --from=builder --chown=nimbus:nimbus /app/_build/prod/rel/nimbus ./

# Switch to non-root user
USER nimbus

# Expose API port
EXPOSE 4000

# Set environment
ENV HOME=/app

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD ["/app/bin/nimbus", "rpc", "IO.puts(:ok)"] || exit 1

# Start the application
CMD ["/app/bin/nimbus", "start"]
