package types

import (
	"math/big"
)

// FilterQuery contains options for contract log filtering.
type FilterQuery struct {
	BlockHash string   // used by eth_getLogs, return logs only from block with this hash
	FromBlock *big.Int // beginning of the queried range, nil means genesis block
	ToBlock   *big.Int // end of the range, nil means latest block
	Addresses []string // restricts matches to events created by specific contracts
	Topics [][]string
}
