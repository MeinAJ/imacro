package v1

import (
	"aave_web/service"
	"encoding/json"
	"fmt"
	"github.com/gin-gonic/gin"
	"log"
	"net/http"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

// 定义WebSocket升级器配置
var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true // 允许所有跨域请求
	},
}

// Client 代表一个WebSocket客户端
type Client struct {
	conn     *websocket.Conn
	send     chan []byte
	clientID string
}

// Message 定义消息结构
type Message struct {
	Type    string      `json:"type"`
	Payload interface{} `json:"payload"`
	Time    int64       `json:"timestamp"`
}

// WSServer WebSocket服务器
type WSServer struct {
	clients    map[*Client]bool
	broadcast  chan []byte
	register   chan *Client
	unregister chan *Client
	mu         sync.RWMutex
	svcCtx     *service.ServerCtx
}

// NewWSServer 新建WebSocket服务器
func NewWSServer(svcCtx *service.ServerCtx) *WSServer {
	wsServer := &WSServer{
		broadcast:  make(chan []byte, 100),
		register:   make(chan *Client),
		unregister: make(chan *Client),
		clients:    make(map[*Client]bool),
		svcCtx:     svcCtx,
	}
	// 启动（注册、注销、广播）
	go wsServer.Run()
	return wsServer
}

// Run 启动WebSocket服务器
func (s *WSServer) Run() {
	ticker := time.NewTicker(15 * time.Second)
	defer ticker.Stop()

	log.Println("WebSocket服务器后台任务启动")

	for {
		select {
		case client := <-s.register:
			s.mu.Lock()
			s.clients[client] = true
			s.mu.Unlock()
			log.Printf("客户端连接: %s, 总连接数: %d", client.clientID, len(s.clients))

		case client := <-s.unregister:
			s.mu.Lock()
			if _, ok := s.clients[client]; ok {
				delete(s.clients, client)
				close(client.send)
			}
			s.mu.Unlock()
			log.Printf("客户端断开: %s, 剩余连接数: %d", client.clientID, len(s.clients))

		case message := <-s.broadcast:
			s.mu.RLock()
			clientCount := len(s.clients)
			if clientCount > 0 {
				for client := range s.clients {
					select {
					case client.send <- message:
						// 消息发送成功
					default:
						// 发送队列满，关闭连接
						close(client.send)
						delete(s.clients, client)
					}
				}
			}
			s.mu.RUnlock()

		case <-ticker.C:
			// 定时发送心跳
			s.mu.RLock()
			clientCount := len(s.clients)
			if clientCount > 0 {
				heartbeatMsg := Message{
					Type:    "heartbeat",
					Payload: fmt.Sprintf("server_ok_%d", time.Now().Unix()),
					Time:    time.Now().Unix(),
				}
				msgBytes, _ := json.Marshal(heartbeatMsg)
				s.broadcast <- msgBytes
				log.Printf("发送心跳到 %d 个客户端", clientCount)
			}
			s.mu.RUnlock()
		}
	}
}

// BroadcastJSON 广播JSON消息
func (s *WSServer) BroadcastJSON(v interface{}) {
	message, err := json.Marshal(v)
	if err != nil {
		log.Printf("JSON编码错误: %v", err)
		return
	}

	select {
	case s.broadcast <- message:
		// 消息成功放入广播通道
	default:
		log.Printf("广播通道已满，丢弃消息")
	}
}

// HandleWebSocket 处理WebSocket连接
func HandleWebSocket(s *WSServer) gin.HandlerFunc {
	return func(c *gin.Context) {
		conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
		if err != nil {
			log.Printf("WebSocket升级失败: %v", err)
			return
		}

		clientID := fmt.Sprintf("%s-%d", c.Request.RemoteAddr, time.Now().UnixNano())
		client := &Client{
			conn:     conn,
			send:     make(chan []byte, 256),
			clientID: clientID,
		}

		s.register <- client

		// 启动读写goroutine
		go s.writePump(client)
		go s.readPump(client)
	}
}

// 写goroutine
func (s *WSServer) writePump(client *Client) {
	ticker := time.NewTicker(30 * time.Second)
	defer func() {
		ticker.Stop()
		err := client.conn.Close()
		if err != nil {
			log.Printf("<UNK>: %v", err)
			return
		}
	}()

	for {
		select {
		case message, ok := <-client.send:
			err := client.conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if err != nil {
				log.Printf("<UNK>: %v", err)
				return
			}
			if !ok {
				// 通道关闭
				err := client.conn.WriteMessage(websocket.CloseMessage, []byte{})
				if err != nil {
					return
				}
				return
			}

			w, err := client.conn.NextWriter(websocket.TextMessage)
			if err != nil {
				return
			}
			write, err := w.Write(message)
			if err != nil {
				log.Printf("<UNK>: %v", err)
				return
			}
			log.Printf("write bytes: %d", write)

			// 写入队列中的其他消息
			n := len(client.send)
			for i := 0; i < n; i++ {
				write, err := w.Write(<-client.send)
				if err != nil {
					log.Printf("<UNK>: %v", err)
					return
				}
				log.Printf("write bytes: %d", write)
			}

			if err := w.Close(); err != nil {
				return
			}

		case <-ticker.C:
			// 发送ping消息
			err := client.conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if err != nil {
				log.Printf("<UNK>: %v", err)
				return
			}
			if err := client.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

// 读goroutine
func (s *WSServer) readPump(client *Client) {
	defer func() {
		s.unregister <- client
		err := client.conn.Close()
		if err != nil {
			log.Printf("<UNK>: %v", err)
			return
		}
	}()

	client.conn.SetReadLimit(51200) // 50KB限制
	err := client.conn.SetReadDeadline(time.Now().Add(60 * time.Second))
	if err != nil {
		log.Printf("<UNK>: %v", err)
		return
	}
	client.conn.SetPongHandler(func(string) error {
		err := client.conn.SetReadDeadline(time.Now().Add(60 * time.Second))
		if err != nil {
			log.Printf("<UNK>: %v", err)
			return err
		}
		return nil
	})

	for {
		_, message, err := client.conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("读取错误: %v", err)
			}
			break
		}

		// 处理客户端消息
		var msg Message
		if err := json.Unmarshal(message, &msg); err == nil {
			s.handleMessage(client, msg)
		} else {
			log.Printf("消息解析错误: %v", err)
		}
	}
}

// 处理客户端消息
func (s *WSServer) handleMessage(client *Client, msg Message) {
	switch msg.Type {
	case "ping":
		// 响应ping消息
		response := Message{
			Type:    "pong",
			Payload: "pong_response",
			Time:    time.Now().Unix(),
		}
		msgBytes, _ := json.Marshal(response)
		client.send <- msgBytes
		log.Printf("客户端 %s 发送ping", client.clientID)

	case "subscribe":
		// 处理订阅请求
		log.Printf("客户端 %s 订阅: %v", client.clientID, msg.Payload)
		response := Message{
			Type:    "subscribed",
			Payload: msg.Payload,
			Time:    time.Now().Unix(),
		}
		msgBytes, _ := json.Marshal(response)
		client.send <- msgBytes

	default:
		log.Printf("收到未知消息类型: %s, 内容: %v", msg.Type, msg.Payload)
	}
}

// PushService 推送服务
type PushService struct {
	wsServer *WSServer
}

func NewPushService(wsServer *WSServer) *PushService {
	return &PushService{wsServer: wsServer}
}

// PushToAll 推送消息给所有客户端
func (ps *PushService) PushToAll(message interface{}) {
	msg := Message{
		Type:    "broadcast",
		Payload: message,
		Time:    time.Now().Unix(),
	}
	ps.wsServer.BroadcastJSON(msg)
}

// StartDataPush 启动数据推送
func (ps *PushService) StartDataPush() {
	go func() {
		ticker := time.NewTicker(3 * time.Second) // 每3秒推送一次
		defer ticker.Stop()

		log.Println("数据推送服务启动")

		for range ticker.C {
			ps.wsServer.mu.RLock()
			clientCount := len(ps.wsServer.clients)
			ps.wsServer.mu.RUnlock()

			if clientCount > 0 {
				data := map[string]interface{}{
					"price":    fmt.Sprintf("%.2f", 10000+100*(time.Now().Second()%60)),
					"volume":   time.Now().Unix() % 10000,
					"market":   "BTC/USDT",
					"updateAt": time.Now().Format("15:04:05"),
					"clients":  clientCount,
				}

				ps.PushToAll(data)
				log.Printf("推送市场数据到 %d 个客户端", clientCount)
			} else {
				log.Printf("没有客户端连接，等待连接...")
			}
		}
	}()
}
