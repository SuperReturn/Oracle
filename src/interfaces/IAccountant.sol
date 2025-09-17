// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

interface IAccountant {
    function getRate() external view returns (uint256);

    struct AccountantState {
        address payoutAddress;
        uint96 highwaterMark;
        uint128 feesOwedInBase;
        uint128 totalSharesLastUpdate;
        uint96 exchangeRate;
        uint16 allowedExchangeRateChangeUpper;
        uint16 allowedExchangeRateChangeLower;
        uint64 lastUpdateTimestamp;
        bool isPaused;
        uint24 minimumUpdateDelayInSeconds;
        uint16 platformFee;
        uint16 performanceFee;
    }

    function accountantState() external view returns (AccountantState memory);
}