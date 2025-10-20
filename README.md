# 实现过程
### 框架搭建
```
cd imacro
npx hardhat init
```

### 安装依赖
```
npm install @openzeppelin/contracts
npm install @openzeppelin/hardhat-upgrades
npm install @chainlink/contracts
npm install dotenv // 作用：将项目根目录下的 .env 文件中的环境变量加载到 process.env 中
```

### 创建.env 文件
```
touch .env

SEPOLIA_ALCHEMY_AK = "BhbGAxZQR2BmhHKXuOsnSUBdMlUfAKHf"
SEPOLIA_PK_ONE = "0x503a1e53dcc6b72f2b85d74d44794cbf65ce198b05db7cb25e6fa22b58cfa532"
SEPOLIA_PK_TWO = "0xa63e18831975456a799bcc971352b16d55459d3525d9954bb5b550f1bfad8418"
SEPOLIA_PK_THREE = "0x4c42dcc67be02d2c1c44d50c3064394f1db90ef56936ab30b6cb21ff3dd471ff"
```

### [编写通用代币合约](solidity/contracts/Token.sol)

### [编写部署AAVE代币、USDC代币、TOSHI代币、DEGEN代币；](solidity/scripts/v1/Aave2Deploy.js)

### 找不到hardhat模块时
```
# 删除node_modules和lock文件
rm -rf node_modules
rm package-lock.json
# 重新安装
npm install
```

### 先本地部署测试
```
npx hardhat node
npx hardhat run scripts/v2/Aave2Deploy.js --network localhost
```

### 再部署到测试网sepolia
``` hardhat
npx hardhat run scripts/v2/Aave2Deploy.js --network sepolia
```

### 部署升级合约时，如果发现新实现地址没变
```
npx hardhat clean
npx hardhat compile --force
```

### [计算event的topic](solidity/scripts/v1/CalculateEventTopic.js)计算event的topic