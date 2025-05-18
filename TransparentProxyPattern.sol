// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title ITransparentUpgradeableProxy
 * @dev Interface for the TransparentUpgradeableProxy contract
 */
interface ITransparentUpgradeableProxy {
    function upgradeTo(address newImplementation) external;
    function upgradeToAndCall(address newImplementation, bytes calldata data) external payable;
}

/**
 * @title TransparentUpgradeableProxy
 * @dev Implementation of the Transparent Proxy Pattern
 * 
 * This contract implements the transparent proxy pattern which separates
 * admin-specific functions from user functions, avoiding function selector
 * clashes by routing calls differently based on the caller's identity.
 * 
 * Storage layout follows EIP-1967 to ensure compatibility and prevent
 * storage collisions with implementation contracts.
 */
contract TransparentUpgradeableProxy {
    /**
     * @dev Storage slot with the address of the current implementation.
     * This is the keccak-256 hash of "eip1967.proxy.implementation" subtracted by 1, and is
     * validated in the constructor.
     */
    bytes32 private constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /**
     * @dev Storage slot with the admin of the contract.
     * This is the keccak-256 hash of "eip1967.proxy.admin" subtracted by 1, and is
     * validated in the constructor.
     */
    bytes32 private constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    /**
     * @dev Emitted when the implementation is upgraded.
     */
    event Upgraded(address indexed implementation);

    /**
     * @dev Emitted when the admin changes.
     */
    event AdminChanged(address previousAdmin, address newAdmin);

    /**
     * @dev Modifier to restrict access to the admin
     */
    modifier ifAdmin() {
        if (msg.sender == _admin()) {
            _;
        } else {
            _fallback();
        }
    }

    /**
     * @dev Initializes the proxy with an implementation address and admin.
     * @param _logic Address of the initial implementation.
     * @param _admin_ Address of the proxy administrator.
     * @param _data Data to send as msg.data to the implementation for initialization.
     */
    constructor(address _logic, address _admin_, bytes memory _data) {
        // Store the implementation address
        _setImplementation(_logic);
        // Store the admin address
        _setAdmin(_admin_);

        // Initialize the implementation if data is provided
        if(_data.length > 0) {
            (bool success,) = _logic.delegatecall(_data);
            require(success, "TransparentUpgradeableProxy: initialization failed");
        }
    }

    /**
     * @dev Upgrades the proxy to a new implementation.
     * Only callable by the admin.
     * @param newImplementation Address of the new implementation.
     */
    function upgradeTo(address newImplementation) external ifAdmin {
        _upgradeTo(newImplementation);
    }

    /**
     * @dev Upgrades the proxy to a new implementation and calls a function on the new implementation.
     * Only callable by the admin.
     * @param newImplementation Address of the new implementation.
     * @param data Function call data to be used as msg.data in the call to the new implementation.
     */
    function upgradeToAndCall(address newImplementation, bytes calldata data) external payable ifAdmin {
        _upgradeTo(newImplementation);
        (bool success,) = newImplementation.delegatecall(data);
        require(success, "TransparentUpgradeableProxy: function call failed");
    }

    /**
     * @dev Changes the admin of the proxy.
     * Only callable by the current admin.
     * @param newAdmin Address of the new admin.
     */
    function changeAdmin(address newAdmin) external ifAdmin {
        require(newAdmin != address(0), "TransparentUpgradeableProxy: new admin is the zero address");
        emit AdminChanged(_admin(), newAdmin);
        _setAdmin(newAdmin);
    }

    /**
     * @dev Returns the current implementation address.
     * Only callable by the admin.
     * @return impl Current implementation address.
     */
    function implementation() external ifAdmin returns (address impl) {
        impl = _implementation();
    }

    /**
     * @dev Returns the current admin address.
     * Only callable by the admin.
     * @return adm Current admin address.
     */
    function admin() external ifAdmin returns (address adm) {
        adm = _admin();
    }

    /**
     * @dev Receives ETH and forwards the call to the implementation contract
     */
    receive() external payable {
        _fallback();
    }

    /**
     * @dev Fallback function that delegates calls to the implementation contract.
     * Will run if call data is empty.
     */
    fallback() external payable {
        _fallback();
    }

    /**
     * @dev Internal function to delegate the current call to the implementation.
     * This is the core functionality of the proxy pattern.
     */
    function _fallback() internal {
        // Check if msg.sender is the admin - if so, we don't delegate admin functions
        require(msg.sender != _admin(), "TransparentUpgradeableProxy: admin cannot fallback to proxy target");
        
        // Get the implementation address
        address _impl = _implementation();
        
        // Execute the delegated call
        assembly {
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize())

            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet.
            let result := delegatecall(gas(), _impl, 0, calldatasize(), 0, 0)

            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())

            switch result
            // delegatecall returns 0 on error.
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    /**
     * @dev Internal function to upgrade the implementation of the proxy.
     * @param newImplementation Address of the new implementation.
     */
    function _upgradeTo(address newImplementation) internal {
        require(newImplementation != address(0), "TransparentUpgradeableProxy: new implementation is the zero address");
        
        // Check the implementation has code
        uint256 codeSize;
        assembly { codeSize := extcodesize(newImplementation) }
        require(codeSize > 0, "TransparentUpgradeableProxy: new implementation has no code");

        // Update the implementation slot
        _setImplementation(newImplementation);
        emit Upgraded(newImplementation);
    }

    /**
     * @dev Internal function to return the current implementation address.
     * @return impl Current implementation address.
     */
    function _implementation() internal view returns (address impl) {
        bytes32 slot = IMPLEMENTATION_SLOT;
        assembly {
            impl := sload(slot)
        }
    }

    /**
     * @dev Internal function to return the current admin address.
     * @return adm Current admin address.
     */
    function _admin() internal view returns (address adm) {
        bytes32 slot = ADMIN_SLOT;
        assembly {
            adm := sload(slot)
        }
    }

    /**
     * @dev Internal function to store a new implementation address.
     * @param newImplementation Address of the new implementation.
     */
    function _setImplementation(address newImplementation) internal {
        bytes32 slot = IMPLEMENTATION_SLOT;
        assembly {
            sstore(slot, newImplementation)
        }
    }

    /**
     * @dev Internal function to store a new admin address.
     * @param newAdmin Address of the new admin.
     */
    function _setAdmin(address newAdmin) internal {
        bytes32 slot = ADMIN_SLOT;
        assembly {
            sstore(slot, newAdmin)
        }
    }
}

/**
 * @title ProxyAdmin
 * @dev Contract that acts as an admin for TransparentUpgradeableProxy contracts.
 * This separation of admin logic enhances security by providing a dedicated
 * contract to manage proxy upgrades.
 */
contract ProxyAdmin {
    address public owner;
    
    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        owner = msg.sender;
    }
    
    /**
     * @dev Modifier to restrict function access to contract owner
     */
    modifier onlyOwner() {
        require(msg.sender == owner, "ProxyAdmin: caller is not the owner");
        _;
    }
    
    /**
     * @dev Changes the owner of the ProxyAdmin contract.
     * @param newOwner Address of the new owner.
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "ProxyAdmin: new owner is the zero address");
        owner = newOwner;
    }

    /**
     * @dev Upgrades a TransparentUpgradeableProxy to a new implementation.
     * @param proxy Address of the TransparentUpgradeableProxy.
     * @param implementation Address of the new implementation.
     */
    function upgrade(address proxy, address implementation) public onlyOwner {
        ITransparentUpgradeableProxy(proxy).upgradeTo(implementation);
    }

    /**
     * @dev Upgrades a TransparentUpgradeableProxy to a new implementation and calls a function
     * on the new implementation.
     * @param proxy Address of the TransparentUpgradeableProxy.
     * @param implementation Address of the new implementation.
     * @param data Function call data to be used in the call to the new implementation.
     */
    function upgradeAndCall(address proxy, address implementation, bytes memory data) public payable onlyOwner {
        ITransparentUpgradeableProxy(proxy).upgradeToAndCall{value: msg.value}(implementation, data);
    }
    
    /**
     * @dev Returns the current implementation of a TransparentUpgradeableProxy.
     * @param proxy Address of the TransparentUpgradeableProxy.
     * @return Address of the current implementation.
     */
    function getProxyImplementation(address proxy) public view returns (address) {
        // We need to manually call the proxy using a low level call
        (bool success, bytes memory returndata) = proxy.staticcall(
            abi.encodeWithSignature("implementation()")
        );
        require(success, "ProxyAdmin: failed to get implementation");
        return abi.decode(returndata, (address));
    }

    /**
     * @dev Returns the admin of a TransparentUpgradeableProxy.
     * @param proxy Address of the TransparentUpgradeableProxy.
     * @return Address of the current admin.
     */
    function getProxyAdmin(address proxy) public view returns (address) {
        // We need to manually call the proxy using a low level call
        (bool success, bytes memory returndata) = proxy.staticcall(
            abi.encodeWithSignature("admin()")
        );
        require(success, "ProxyAdmin: failed to get admin");
        return abi.decode(returndata, (address));
    }
}

/**
 * @title Box
 * @dev Example implementation contract V1 that can be upgraded.
 * This simple contract stores and retrieves a value.
 */
contract Box {
    // Storage variable
    uint256 private _value;
    
    // Event emitted when the stored value changes
    event ValueChanged(uint256 newValue);
    
    // Function to store a new value
    function store(uint256 newValue) public {
        _value = newValue;
        emit ValueChanged(newValue);
    }
    
    // Function to retrieve the stored value
    function retrieve() public view returns (uint256) {
        return _value;
    }
}

/**
 * @title BoxV2
 * @dev Upgraded version of the Box contract with additional functionality.
 * Maintains the same storage layout as Box but adds an increment function.
 */
contract BoxV2 {
    // Storage variable (must match Box for upgradeability)
    uint256 private _value;
    
    // Event emitted when the stored value changes
    event ValueChanged(uint256 newValue);
    
    // Function to store a new value (same as Box)
    function store(uint256 newValue) public {
        _value = newValue;
        emit ValueChanged(newValue);
    }
    
    // Function to retrieve the stored value (same as Box)
    function retrieve() public view returns (uint256) {
        return _value;
    }
    
    // New function in V2: increment the stored value
    function increment() public {
        _value = _value + 1;
        emit ValueChanged(_value);
    }
}