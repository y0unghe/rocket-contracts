// SPDX-License-Identifier: MIT
pragma solidity =0.8.24;

import {Create2} from "openzeppelin-contracts/contracts/utils/Create2.sol";
import {FairLaunchLimitBlockTokenV3} from "./FairLaunchLimitBlockV3.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IFairLaunch, FairLaunchLimitBlockStruct} from "./IFairLaunch.sol";

/**
To new issuers, in order to avoid this situation, 
please use the factory contract to deploy the Token contract when deploying new contracts in the future. 

Please use a new address that has not actively initiated transactions on any chain to deploy. 
The factory contract can create the same address on each evm chain through the create2 function. 
If a player transfers ETHs to the wrong chain, you can also help the player get his ETH back by refunding his money by deploying a contract on a specific chain.
 */
contract FairLaunchLimitBlockV3Factory is IFairLaunch, ReentrancyGuard {
    address public owner;

    address public immutable locker;

    mapping(address => bool) public allowlist;

    // owner modifier
    modifier onlyOwner() {
        require(msg.sender == owner, "only owner");
        _;
    }

    constructor(address _locker, address _positionManager, address _factory) {
        owner = msg.sender;
        locker = _locker;

        allowlist[_positionManager] = true;
        allowlist[_factory] = true;
    }

    function setOwner(address _owner) public onlyOwner {
        owner = _owner;
    }

    function getFairLaunchLimitBlockV3Address(
        uint256 salt,
        address _projectOwner,
        FairLaunchLimitBlockStruct memory params
    ) public view returns (address) {
        bytes32 _salt = keccak256(abi.encodePacked(salt));
        return
            Create2.computeAddress(
                _salt,
                keccak256(
                    abi.encodePacked(
                        type(FairLaunchLimitBlockTokenV3).creationCode,
                        abi.encode(locker, _projectOwner, params)
                    )
                )
            );
    }

    function deployFairLaunchLimitBlockV3Contract(
        uint256 salt, // random number as salt
        address _projectOwner,
        FairLaunchLimitBlockStruct memory params
    ) public payable nonReentrant {
        require(
            allowlist[params.uniswapFactory] && allowlist[params.uniswapRouter],
            "Uniswap factory or router should be in allowlist."
        );

        bytes32 _salt = keccak256(abi.encodePacked(salt));
        bytes memory bytecode = abi.encodePacked(
            type(FairLaunchLimitBlockTokenV3).creationCode,
            abi.encode(locker, _projectOwner, params)
        );
        address addr = Create2.deploy(0, _salt, bytecode);
        emit Deployed(addr);
    }
}
