// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "./interfaces/IAccountant.sol";

contract MockAccountant is IAccountant {
    AccountantState private _state;

    error AccountantWithRateProviders__Paused();

    // Constructor with default values
    constructor() {
        _state = AccountantState({
            payoutAddress: address(this),
            highwaterMark: 1032023,
            feesOwedInBase: 0,
            totalSharesLastUpdate: 0,
            exchangeRate: 1032023,
            allowedExchangeRateChangeUpper: 10050, // 10%
            allowedExchangeRateChangeLower: 9950, // 10%
            lastUpdateTimestamp: 1758184085,
            isPaused: false,
            minimumUpdateDelayInSeconds: 0, // 1 hour
            platformFee: 0, // 1%
            performanceFee: 0 // 10%
        });
    }

    // Implementation of IAccountant interface
    function getRate() external view override returns (uint256) {
        return _state.exchangeRate;
    }

    function getRateSafe() external view override returns (uint256) {
        if (_state.isPaused) revert AccountantWithRateProviders__Paused();
        return _state.exchangeRate;
    }

    function accountantState() external view override returns (AccountantState memory) {
        return _state;
    }

    // Additional functions for mock control
    function setRate(uint256 newRate, uint256 newLastUpdateTimestamp) external {
        _state.exchangeRate = uint96(newRate);
        _state.lastUpdateTimestamp = uint64(newLastUpdateTimestamp);
    }

    function setState(AccountantState calldata newState) external {
        _state = newState;
    }
}
