// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {ForkTestBase} from "../lib/ForkTestBase.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {PermissionLib} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {PaymentsPlugin} from "../../src/PaymentsPlugin.sol";
import {PaymentsPluginSetup} from "../../src/setup/PaymentsPluginSetup.sol";
import {AddressRegistry} from "../../src/AddressRegistry.sol";
import {ILlamaPayFactory} from "../../src/interfaces/ILlamaPay.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ProxyLib} from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyLib.sol";

contract PaymentsForkBuilder is ForkTestBase {
    // Add your own parameters here
    address manager = bob;
    address registryAddress;
    address llamaPayFactoryAddress;
    address tokenAddress;
    address whaleAddress;

    // Environmental variables from .env
    address constant LLAMAPAY_FACTORY_BASE = 0x09c39B8311e4B7c678cBDAD76556877ecD3aEa07;
    address constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant USDC_WHALE = 0x0B0A5886664376F59C351ba3f598C8A8B4D0A6f3;

    constructor() {
        // Default to Base mainnet addresses
        withLlamaPayFactory(LLAMAPAY_FACTORY_BASE);
        withToken(USDC_BASE);
        withWhale(USDC_WHALE);
    }

    function withManager(address _manager) public returns (PaymentsForkBuilder) {
        manager = _manager;
        return this;
    }

    function withRegistry(address _registry) public returns (PaymentsForkBuilder) {
        registryAddress = _registry;
        return this;
    }

    function withLlamaPayFactory(address _factory) public returns (PaymentsForkBuilder) {
        llamaPayFactoryAddress = _factory;
        return this;
    }

    function withToken(address _token) public returns (PaymentsForkBuilder) {
        tokenAddress = _token;
        return this;
    }

    function withWhale(address _whale) public returns (PaymentsForkBuilder) {
        whaleAddress = _whale;
        return this;
    }

    /// @dev Creates a DAO with the PaymentsPlugin for fork testing
    /// @dev Bypasses the DAOFactory to avoid permission issues on forked networks
    function build()
        public
        returns (
            DAO dao,
            PaymentsPluginSetup setup,
            PaymentsPlugin plugin,
            AddressRegistry registry,
            ILlamaPayFactory llamaPayFactory,
            IERC20 token
        )
    {
        // Deploy or use provided registry
        if (registryAddress == address(0)) {
            registry = AddressRegistry(ProxyLib.deployUUPSProxy(address(new AddressRegistry()), ""));
            registryAddress = address(registry);
        } else {
            registry = AddressRegistry(registryAddress);
        }

        // Use real LlamaPay factory and token
        llamaPayFactory = ILlamaPayFactory(llamaPayFactoryAddress);
        token = IERC20(tokenAddress);

        // Deploy DAO directly
        dao = DAO(
            payable(
                ProxyLib.deployUUPSProxy(
                    address(new DAO()), abi.encodeCall(DAO.initialize, ("", address(this), address(0x0), ""))
                )
            )
        );

        // Deploy plugin setup
        setup = new PaymentsPluginSetup();

        // Deploy plugin via setup's prepareInstallation
        bytes memory installParams = setup.encodeInstallationParams(manager, registryAddress, llamaPayFactoryAddress);

        (address pluginAddress,) = setup.prepareInstallation(address(dao), installParams);
        plugin = PaymentsPlugin(pluginAddress);

        // Manually grant permissions that would normally be done by PluginSetupProcessor
        // Grant MANAGER_PERMISSION on plugin to manager
        dao.grant(address(plugin), manager, plugin.MANAGER_PERMISSION_ID());

        // Grant EXECUTE_PERMISSION on DAO to plugin
        dao.grant(address(dao), address(plugin), dao.EXECUTE_PERMISSION_ID());

        // Fund the DAO with tokens from whale
        vm.startPrank(whaleAddress);
        uint256 whaleBalance = token.balanceOf(whaleAddress);
        require(whaleBalance >= 10000e6, "Whale has insufficient balance");
        token.transfer(address(dao), 10000e6); // 10,000 USDC
        vm.stopPrank();

        // Labels
        vm.label(address(dao), "DAO");
        vm.label(address(plugin), "PaymentsPlugin");
        vm.label(address(registry), "AddressRegistry");
        vm.label(address(llamaPayFactory), "LlamaPayFactory");
        vm.label(address(token), "USDC");
        vm.label(whaleAddress, "USDC_WHALE");

        // Moving forward to avoid collisions
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
    }
}
