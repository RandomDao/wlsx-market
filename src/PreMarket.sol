// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./Project.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract PreMarket is Ownable {
    uint256 public counter = 0;

    Project public project;

    constructor(address projectAddress) Ownable(msg.sender) {
        project = Project(projectAddress);
    }

    /**
     * 这两个挂单列表，不维护顺序，且当吃单后，删除数组中的数据。
     */
    mapping(uint256 => uint256[]) public sellPreOrders; //项目id=>卖单挂单列表
    mapping(uint256 => uint256[]) public buyPreOrders; //项目id=>买单挂单列表

    mapping(address => uint256[]) public userOrder; //用户address=>订单
    mapping(uint256 => uint256[]) public peojectOrder; //项目id=>订单

    mapping(uint256 => PreOrder) public orders; //订单id=>订单，统一存储所有订单的map

    event AddOrder(uint256 projectId, uint256 orderId, PreOrder order);
    event MatchOrder(uint256 projectId, uint256 orderId, PreOrder order);

    /**
     * 挂单
     */
    function addOrder(uint256 projectId, uint256 amount, uint256 deposit, uint8 depositType, uint8 buyOrSell)
        public
        payable
    {
        require(msg.value == deposit, "deposit error");
        PreOrder memory order = PreOrder({
            orderId: counter++,
            projectId: projectId,
            buyer: msg.sender,
            seller: address(0),
            amount: amount,
            deposit: deposit,
            depositType: depositType,
            status: 0
        });
        if (buyOrSell == 0) {
            order.buyer = msg.sender;
            buyPreOrders[projectId].push(order.orderId);
        } else {
            order.seller = msg.sender;
            sellPreOrders[projectId].push(order.orderId);
        }
        peojectOrder[projectId].push(order.orderId);
        orders[order.orderId] = order;
        emit AddOrder(projectId, order.orderId, order);
    }

    /**
     * 吃单
     */
    function matchOrder(uint256 projectId, uint256 orderId, uint256 fillAmount) public payable {
        PreOrder storage order = orders[orderId];
        bool isBuy = order.buyer != address(0);
        //TODO 待做拆单，先假设一次性成交
        require(fillAmount == order.amount, "fillAmount error");
        require(msg.value == order.deposit, "deposit error");

        //设置单子
        if (isBuy) {
            order.seller = msg.sender;
        } else {
            order.buyer = msg.sender;
        }
        order.status = 1;

        //TODO 生成ERC6551给双方
        uint256[] storage preOrders = isBuy ? buyPreOrders[projectId] : sellPreOrders[projectId];

        deleteOrder(preOrders, orderId);
        emit MatchOrder(projectId, orderId, order);
    }

    /**
     * 交割
     */
    function delivery(uint256 orderId) public {
        PreOrder storage order = orders[orderId];
        require(order.status == 1, "status error");
        require(msg.sender == order.seller, "permission error");

        Project.PreProject memory prj = project.getProject(order.projectId);
        require(prj.TGETime < block.timestamp && prj.deliveryEndTime > block.timestamp, "cannot delivery");

        IERC20(prj.token).transferFrom(msg.sender, order.buyer, order.amount);

        //将钱转给卖家
        Address.sendValue(payable(msg.sender), 2 * order.deposit);
        order.status = 4;
    }

    /**
     * 取消挂单
     */
    function cancel(uint256 orderId) public {
        PreOrder storage order = orders[orderId];
        require(order.status == 1, "cannot cancel");
        require(order.buyer == msg.sender || order.seller == msg.sender, "cannot cancel");
        bool isBuy = order.buyer != address(0);
        uint256[] storage preOrders = isBuy ? buyPreOrders[order.projectId] : sellPreOrders[order.projectId];

        deleteOrder(preOrders, orderId);
        Address.sendValue(payable(msg.sender), order.deposit);
    }

    /**
     * 获取所有挂单列表,无顺序
     * @param projectId 项目id
     * @param buyOrSell 0:买单 1:卖单
     */
    function preOrdersList(uint256 projectId, uint8 buyOrSell) public view returns (PreOrder[] memory) {
        uint256[] storage list = buyOrSell == 0 ? buyPreOrders[projectId] : sellPreOrders[projectId];
        PreOrder[] memory result = new PreOrder[](list.length);

        for (uint256 i = 0; i < list.length; i++) {
            result[i] = orders[list[i]];
        }
        return result;
    }

    /**
     * 违约后，买家取款
     */
    function repay(uint256 orderId) public {
        PreOrder storage order = orders[orderId];
        require(order.buyer == msg.sender, "permission error");
        Project.PreProject memory prj = project.getProject(order.projectId);

        require(order.status == 3 || (order.status == 2 && prj.deliveryEndTime < block.timestamp), "status error");
        Address.sendValue(payable(msg.sender), 2 * order.deposit);
    }

    /**
     * TODO 用户交易历史
     */
    function profilo() public view returns (uint256) {
        return address(this).balance;
    }

    function deleteOrder(uint256[] storage preOrders, uint256 orderId) private {
        //删除挂单数组中对应的单子
        for (uint256 i = 0; i < preOrders.length; i++) {
            if (preOrders[i] == orderId) {
                preOrders[i] = preOrders[preOrders.length - 1];
                preOrders.pop();
                break;
            }
        }
    }

    /*---------------------------管理员调用-----------------------------------------------*/

    //设置订单状态。也可以不设置，前端判断状态，设置按钮状态
    function setOrderStatus(uint256 projectId, uint8 status) public onlyOwner {
        uint256[] storage projects = peojectOrder[projectId];
        for (uint256 i = 0; i < projects.length; i++) {
            PreOrder storage order = orders[projects[i]];
            if (order.status == 1) {
                order.status = status;
            }
        }
    }

    struct PreOrder {
        uint256 orderId;
        uint256 projectId; //项目id
        address buyer;
        address seller;
        uint256 amount; //数量
        uint256 deposit; //押金
        uint8 depositType; //押金类型 0:USDT 1:ETH
        uint8 status; //状态 0:已挂单 1:已配对 2:交割窗口内，待交割 3:未交割已过期 4:已结束（2，3最终都变为4）
    }
}
