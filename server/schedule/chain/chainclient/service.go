package chainclient

import (
	"aave_schedule/chain"
	"aave_schedule/chain/chainclient/evmclient"
	"context"
	"math/big"

	"github.com/ethereum/go-ethereum"
	"github.com/pkg/errors"

	logTypes "aave_schedule/chain/types"
)

type ChainClient interface {
	FilterLogs(ctx context.Context, q logTypes.FilterQuery) ([]interface{}, error)
	BlockTimeByNumber(context.Context, *big.Int) (uint64, error)
	Client() interface{}
	CallContract(ctx context.Context, msg ethereum.CallMsg, blockNumber *big.Int) ([]byte, error)
	CallContractByChain(ctx context.Context, param logTypes.CallParam) (interface{}, error)
	BlockNumber() (uint64, error)
	BlockWithTxs(ctx context.Context, blockNumber uint64) (interface{}, error)
}

func New(chainID int, nodeUrl string) (ChainClient, error) {
	switch chainID {
	case chain.EthChainID, chain.OptimismChainID, chain.SepoliaChainID:
		return evmclient.New(nodeUrl)
	default:
		return nil, errors.New("unsupported chain id")
	}
}
