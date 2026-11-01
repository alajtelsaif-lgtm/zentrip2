package com.zentrip.api;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
public class ExchangeRateController {
    private final ExchangeRateService rates;

    public ExchangeRateController(ExchangeRateService rates) {
        this.rates = rates;
    }

    @GetMapping("/api/exchange-rates")
    public Map<String, Object> latest() {
        return rates.latest();
    }
}
