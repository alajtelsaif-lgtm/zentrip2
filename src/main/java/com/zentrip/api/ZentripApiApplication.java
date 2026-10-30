package com.zentrip.api;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableAsync;

@SpringBootApplication
@EnableAsync
public class ZentripApiApplication {
    public static void main(String[] args) {
        SpringApplication.run(ZentripApiApplication.class, args);
    }
}