# 构建阶段
FROM golang:1.24.4-alpine AS builder

WORKDIR /app

# 先复制依赖文件，利用Docker缓存
COPY go.mod go.sum ./
RUN go mod download

# 复制所有源代码
COPY . .

# 构建静态链接的可执行文件
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s -extldflags '-static'" -o main .

# 使用alpine基础镜像（包含时区数据）
FROM alpine:3.20

# 安装时区数据
RUN apk add --no-cache tzdata

# 设置时区
ENV TZ=Asia/Shanghai

# 创建配置目录
RUN mkdir -p /app/config

# 复制可执行文件和配置文件
COPY --from=builder /app/main /
COPY --from=builder /app/config/config.toml /app/config/

WORKDIR /

# 暴露端口
EXPOSE 8080

# 健康检查
HEALTHCHECK --interval=30s --timeout=3s \
    CMD ["/main", "healthcheck"]

# 启动应用，指定配置文件路径
CMD ["/main", "-conf", "/app/config/config.toml"]