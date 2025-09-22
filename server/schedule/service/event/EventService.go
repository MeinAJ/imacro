package event

import (
	"aave_schedule/chain/chainclient"
	chainTypes "aave_schedule/chain/types"
	"aave_schedule/config"
	"aave_schedule/logger/xzap"
	"aave_schedule/stores/xkv"
	"aave_schedule/types"
	"context"
	"encoding/json"
	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common"
	ethereumTypes "github.com/ethereum/go-ethereum/core/types"
	"github.com/zeromicro/go-zero/core/threading"
	"go.uber.org/zap"
	"gorm.io/gorm"
	"math/big"
	"strconv"
	"strings"
	"time"
)

type Service struct {
	ctx         context.Context
	cfg         *config.Config
	db          *gorm.DB
	kv          *xkv.Store
	chainClient chainclient.ChainClient
	chainId     int64
	chain       string
	parsedAbi   abi.ABI
}

var MultiChainMaxBlockDifference = map[string]uint64{
	"eth":        1,
	"optimism":   2,
	"starknet":   1,
	"arbitrum":   2,
	"base":       2,
	"zksync-era": 2,
}

func New(ctx context.Context, cfg *config.Config, db *gorm.DB, xkv *xkv.Store, chainClient chainclient.ChainClient, chainId int64, chain string) *Service {
	parsedAbi, _ := abi.JSON(strings.NewReader(cfg.ContractCfg.AbiJson)) // 通过ABI实例化
	return &Service{
		ctx:         ctx,
		cfg:         cfg,
		db:          db,
		kv:          xkv,
		chainClient: chainClient,
		chain:       chain,
		chainId:     chainId,
		parsedAbi:   parsedAbi,
	}
}

func (s *Service) Start() {
	// 同步区块链上的事件
	threading.GoSafe(s.SyncAaveEventLoop)
}

func (s *Service) SyncAaveEventLoop() {
	var indexedStatus types.IndexedStatus
	err := s.db.WithContext(s.ctx).
		Select("chain_id,last_indexed_block,last_indexed_time").
		Table(types.GetIndexedStatusTableName()).
		Where("chain_id = ?", s.chainId).
		First(&indexedStatus).Error
	if err != nil {
		xzap.WithContext(s.ctx).Error("get indexed status error", zap.Error(err))
		return
	}
	if indexedStatus.LastIndexedTime >= time.Now().Unix() {
		// 上次同步时间大于当前时间，直接返回，说明时间有问题
		return
	}
	var beginBlockNumber = uint64(indexedStatus.LastIndexedBlock)
	for {
		// 直接修改indexedStatus的LastIndexedBlock为beginBlockNumber，避免重复同步
		err := s.db.WithContext(s.ctx).
			Table(types.GetIndexedStatusTableName()).
			Where("chain_id = ?", s.chainId).
			Update("last_indexed_block", beginBlockNumber).Error
		if err != nil {
			xzap.WithContext(s.ctx).Error("update indexed status error", zap.Error(err))
			time.Sleep(5 * time.Second)
			continue
		}
		select {
		case <-s.ctx.Done():
			xzap.WithContext(s.ctx).Info("SyncAaveEventLoop stopped due to context cancellation")
			return
		default:
		}
		currentBlockNumber, err := s.chainClient.BlockNumber()
		if err != nil {
			// 网络错误，等待5秒后再次尝试
			xzap.WithContext(s.ctx).Error("failed on get current block number, wait 5 seconds", zap.Error(err))
			time.Sleep(5 * time.Second)
			continue
		}
		if currentBlockNumber < beginBlockNumber {
			// 区块高度没有更新，等待5秒后再次尝试
			xzap.WithContext(s.ctx).Info("current block number is not updated, wait 5 seconds")
			time.Sleep(5 * time.Second)
			continue
		}
		// 免费节点限制最多10个，这里设置为5个
		endBlockNumber := beginBlockNumber + 5
		if endBlockNumber > currentBlockNumber {
			endBlockNumber = currentBlockNumber
		}
		xzap.WithContext(s.ctx).Info("begin block number is " + strconv.FormatUint(beginBlockNumber, 10) + " end block number is " + strconv.FormatUint(endBlockNumber, 10))
		// 确定了开始和结束的区块高度，开始同步事件
		filterQuery := chainTypes.FilterQuery{
			FromBlock: new(big.Int).SetUint64(beginBlockNumber),
			ToBlock:   new(big.Int).SetUint64(endBlockNumber),
			Addresses: []string{s.cfg.ContractCfg.AavePoolAddress},
		}
		// 开始查询过滤日志
		filterLogs, err := s.chainClient.FilterLogs(s.ctx, filterQuery)
		if err != nil {
			xzap.WithContext(s.ctx).Error("filter logs error, wait 5 seconds", zap.Error(err))
			time.Sleep(5 * time.Second)
			beginBlockNumber = endBlockNumber + 1
			continue
		}
		if len(filterLogs) == 0 {
			// 没有日志，说明没有新的事件，继续下一个区块
			beginBlockNumber = endBlockNumber + 1
			continue
		}
		for _, log := range filterLogs {
			ethLog := log.(ethereumTypes.Log)
			xzap.WithContext(s.ctx).Info("filter log", zap.Any("event_topic", ethLog.Topics[0].String()))
			switch ethLog.Topics[0].String() {
			case s.cfg.ContractCfg.DepositLendTopic:
				xzap.WithContext(s.ctx).Info("handle deposit lend event", zap.String("topic", ethLog.Topics[0].String()))
				s.handleDepositLendEvent(ethLog)
			case s.cfg.ContractCfg.DepositLendWithdrawTopic:
				xzap.WithContext(s.ctx).Info("handle deposit lend withdraw event", zap.String("topic", ethLog.Topics[0].String()))
				s.handleDepositLendWithdrawEvent(ethLog)
			case s.cfg.ContractCfg.DepositBorrowTopic:
				xzap.WithContext(s.ctx).Info("handle deposit borrow event", zap.String("topic", ethLog.Topics[0].String()))
				s.handleDepositBorrowEvent(ethLog)
			case s.cfg.ContractCfg.DepositBorrowWithdrawTopic:
				xzap.WithContext(s.ctx).Info("handle deposit borrow withdraw event", zap.String("topic", ethLog.Topics[0].String()))
				s.handleDepositBorrowWithdrawEvent(ethLog)
			case s.cfg.ContractCfg.LiquidateTopic:
				xzap.WithContext(s.ctx).Info("handle liquidate event", zap.String("topic", ethLog.Topics[0].String()))
				s.handleLiquidateEvent(ethLog)
			case s.cfg.ContractCfg.CalculateBorrowableTopic:
				xzap.WithContext(s.ctx).Info("handle calculate borrowable event", zap.String("topic", ethLog.Topics[0].String()))
				s.handleCalculateBorrowableEvent(ethLog)
			case s.cfg.ContractCfg.StatusChangedTopic:
				xzap.WithContext(s.ctx).Info("handle status changed event", zap.String("topic", ethLog.Topics[0].String()))
				s.handleStatusChangedEvent(ethLog)
			case s.cfg.ContractCfg.CollateralChangedTopic:
				xzap.WithContext(s.ctx).Info("handle collateral changed event", zap.String("topic", ethLog.Topics[0].String()))
				s.handleCollateralChangedEvent(ethLog)
			default:
			}
			// 最后通知，合约状态发生变化
			s.eventNotify()
		}
		beginBlockNumber = endBlockNumber + 1
	}
}

func (s *Service) handleDepositLendEvent(log ethereumTypes.Log) {
	// 检查 topics 数量是否正确（至少要有事件签名和1个indexed参数）
	if len(log.Topics) < 1 {
		xzap.WithContext(s.ctx).Error("Insufficient topics for DepositLend event",
			zap.Int("topics_count", len(log.Topics)))
		return
	}

	// 定义事件结构体
	var event struct {
		User   common.Address // indexed 参数，从 topics 中解析
		Pool   common.Address // 非 indexed 参数，从 data 中解析
		Amount *big.Int       // 非 indexed 参数，从 data 中解析
	}

	// 1. 解析 indexed 参数 (user) - 从 topics[1] 中提取
	// topics[0] 是事件签名哈希，topics[1] 是第一个 indexed 参数 (user)
	event.User = common.BytesToAddress(log.Topics[1].Bytes())

	// 2. 解析非 indexed 参数 (pool 和 amount) 从 data 字段
	err := s.parsedAbi.UnpackIntoInterface(&event, "DepositLend", log.Data)
	if err != nil {
		xzap.WithContext(s.ctx).Error("Error unpacking DepositLend event data",
			zap.Error(err),
			zap.String("data_hex", common.Bytes2Hex(log.Data)),
			zap.Int("data_length", len(log.Data)),
			zap.String("tx_hash", log.TxHash.Hex()))
		return
	}

	// 3. 验证解析结果
	if event.Pool == (common.Address{}) {
		xzap.WithContext(s.ctx).Warn("Pool address is zero",
			zap.String("tx_hash", log.TxHash.Hex()))
	}

	if event.Amount == nil || event.Amount.Sign() <= 0 {
		xzap.WithContext(s.ctx).Warn("Amount is zero or negative",
			zap.String("tx_hash", log.TxHash.Hex()))
		return
	}

	// 4. 记录解析成功的信息
	xzap.WithContext(s.ctx).Info("DepositLend event parsed successfully",
		zap.String("user", event.User.Hex()),
		zap.String("pool", event.Pool.Hex()),
		zap.String("amount", event.Amount.String()),
		zap.String("tx_hash", log.TxHash.Hex()),
		zap.Uint64("block_number", log.BlockNumber),
		zap.Uint("log_index", log.Index),
	)

	// 5. todo 修改lend记录，这里简单了，流程已经通了

}

func (s *Service) handleDepositLendWithdrawEvent(log ethereumTypes.Log) {

}

func (s *Service) handleDepositBorrowEvent(log ethereumTypes.Log) {

}

func (s *Service) handleDepositBorrowWithdrawEvent(log ethereumTypes.Log) {

}

func (s *Service) handleLiquidateEvent(log ethereumTypes.Log) {

}

func (s *Service) handleCalculateBorrowableEvent(log ethereumTypes.Log) {

}

func (s *Service) handleStatusChangedEvent(log ethereumTypes.Log) {
	// 检查 topics 数量是否正确
	if len(log.Topics) != 1 {
		xzap.WithContext(s.ctx).Error("Insufficient topics for StatusChanged event",
			zap.Int("topics_count", len(log.Topics)))
		return
	}

	// 定义事件结构体
	var event struct {
		UtilizationRate *big.Int // 非 indexed 参数，从 data 中解析
		TotalBorrow     *big.Int // 非 indexed 参数，从 data 中解析
		TotalDeposits   *big.Int // 非 indexed 参数，从 data 中解析
		InterestRate    *big.Int // 非 indexed 参数，从 data 中解析
	}

	// 解析非 indexed 参数 (pool 和 amount) 从 data 字段
	err := s.parsedAbi.UnpackIntoInterface(&event, "StatusChanged", log.Data)
	if err != nil {
		xzap.WithContext(s.ctx).Error("Error unpacking StatusChanged event data",
			zap.Error(err),
			zap.String("data_hex", common.Bytes2Hex(log.Data)),
			zap.Int("data_length", len(log.Data)),
			zap.String("tx_hash", log.TxHash.Hex()))
		return
	}

	// 4. 记录解析成功的信息
	xzap.WithContext(s.ctx).Info("StatusChanged event parsed successfully",
		zap.String("utilizationRate", event.UtilizationRate.String()),
		zap.String("totalBorrow", event.TotalBorrow.String()),
		zap.String("totalDeposits", event.TotalDeposits.String()),
		zap.String("interestRate", event.InterestRate.String()),
		zap.String("tx_hash", log.TxHash.Hex()),
		zap.Uint64("block_number", log.BlockNumber),
		zap.Uint("log_index", log.Index),
	)
	// 5. 直接新增一条lend记录
	if err := s.db.WithContext(s.ctx).Table(types.GetLendTableName()).Create(&types.Lend{
		Type:            0,
		TotalBorrow:     event.TotalBorrow.String(),
		TotalDeposits:   event.TotalDeposits.String(),
		UtilizationRate: int(event.UtilizationRate.Int64()),
		InterestRate:    int(event.InterestRate.Int64()),
		CreateTime:      int(time.Now().Unix()),
		UpdateTime:      int(time.Now().Unix()),
		Creator:         "system",
		Updater:         "system",
	}).Error; err != nil {
		xzap.WithContext(s.ctx).Error("Error creating Lend", zap.Error(err))
	}

}

func (s *Service) handleCollateralChangedEvent(log ethereumTypes.Log) {
	// 检查 topics 数量是否正确
	if len(log.Topics) != 2 {
		xzap.WithContext(s.ctx).Error("Insufficient topics for CollateralChanged event",
			zap.Int("topics_count", len(log.Topics)))
		return
	}

	// 定义事件结构体
	var event struct {
		TokenAddress           common.Address // indexed 参数，从 topics 中解析
		UtilizationRate        *big.Int       // 非 indexed 参数，从 data 中解析
		Borrowed               *big.Int       // 非 indexed 参数，从 data 中解析
		Borrowable             *big.Int       // 非 indexed 参数，从 data 中解析
		InterestRate           *big.Int       // 非 indexed 参数，从 data 中解析
		HealthFactor           *big.Int       // 非 indexed 参数，从 data 中解析
		LiquidationThreshold   *big.Int       // 非 indexed 参数，从 data 中解析
		CollateralizationRatio *big.Int       // 非 indexed 参数，从 data 中解析
	}

	// 取topics的第二个
	event.TokenAddress = common.BytesToAddress(log.Topics[1].Bytes())

	// 解析非 indexed 参数 (pool 和 amount) 从 data 字段
	err := s.parsedAbi.UnpackIntoInterface(&event, "CollateralChanged", log.Data)
	if err != nil {
		xzap.WithContext(s.ctx).Error("Error unpacking CollateralChanged event data",
			zap.Error(err),
			zap.String("data_hex", common.Bytes2Hex(log.Data)),
			zap.Int("data_length", len(log.Data)),
			zap.String("tx_hash", log.TxHash.Hex()))
		return
	}

	// 4. 记录解析成功的信息
	xzap.WithContext(s.ctx).Info("CollateralChanged event parsed successfully",
		zap.String("TokenAddress", event.UtilizationRate.String()),
		zap.String("UtilizationRate", event.UtilizationRate.String()),
		zap.String("Borrowed", event.Borrowed.String()),
		zap.String("Borrowable", event.Borrowable.String()),
		zap.String("InterestRate", event.InterestRate.String()),
		zap.String("HealthFactor", event.HealthFactor.String()),
		zap.String("LiquidationThreshold", event.LiquidationThreshold.String()),
		zap.String("CollateralizationRatio", event.CollateralizationRatio.String()),
		zap.String("tx_hash", log.TxHash.Hex()),
		zap.Uint64("block_number", log.BlockNumber),
		zap.Uint("log_index", log.Index),
	)

	// 5. 直接新增一条collateral记录
	var tokenAddressMap map[string]int
	err = json.Unmarshal([]byte(s.cfg.ContractCfg.TokenAddressMap), &tokenAddressMap)
	if err != nil {
		xzap.WithContext(s.ctx).Error("Error marshalling contract cfg TokenAddressMap", zap.Error(err))
		return
	}
	if err := s.db.WithContext(s.ctx).Table(types.GetCollateralTableName()).Create(&types.Collateral{
		TokenAddress:          event.TokenAddress.String(),
		Type:                  tokenAddressMap[event.TokenAddress.String()],
		Borrowed:              event.Borrowed.String(),
		Borrowable:            event.Borrowable.String(),
		UtilizationRate:       int(event.UtilizationRate.Int64()),
		InterestRate:          int(event.InterestRate.Int64()),
		HealthFactor:          int(event.HealthFactor.Int64()),
		LiquidationThreshold:  int(event.LiquidationThreshold.Int64()),
		CollateralizationRate: int(event.CollateralizationRatio.Int64()),
		CreateTime:            int(time.Now().Unix()),
		UpdateTime:            int(time.Now().Unix()),
		Creator:               "system",
		Updater:               "system",
	}).Error; err != nil {
		xzap.WithContext(s.ctx).Error("Error creating Collateral", zap.Error(err))
	}
}

func (s *Service) eventNotify() {
	s.kv.Store.Lpush(getNotifyQueue(), "1")
}

func getNotifyQueue() string {
	return "aave:event:CollateralChanged"
}
