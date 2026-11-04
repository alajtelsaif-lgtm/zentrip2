package com.zentrip.api;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import java.util.List;
import org.junit.jupiter.api.Test;

class WebConfigTest {
    @Test
    void parsesOnlyDistinctExactHttpOrigins() {
        assertEquals(
                List.of("https://app.example.test", "http://localhost:5173"),
                WebConfig.parseExactOrigins(
                        " https://app.example.test, http://localhost:5173,https://app.example.test "));
        assertEquals(List.of(), WebConfig.parseExactOrigins("  "));
    }

    @Test
    void rejectsWildcardOrigins() {
        assertThrows(IllegalArgumentException.class,
                () -> WebConfig.parseExactOrigins("https://*.example.test"));
        assertThrows(IllegalArgumentException.class,
                () -> WebConfig.parseExactOrigins("*"));
    }

    @Test
    void rejectsPathsQueriesAndNonHttpSchemes() {
        assertThrows(IllegalArgumentException.class,
                () -> WebConfig.parseExactOrigins("https://app.example.test/"));
        assertThrows(IllegalArgumentException.class,
                () -> WebConfig.parseExactOrigins("https://app.example.test/path"));
        assertThrows(IllegalArgumentException.class,
                () -> WebConfig.parseExactOrigins("file://app.example.test"));
    }
}
