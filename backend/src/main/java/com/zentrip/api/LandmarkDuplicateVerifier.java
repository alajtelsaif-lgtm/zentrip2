package com.zentrip.api;

import java.util.Map;

public interface LandmarkDuplicateVerifier {
    boolean isAvailable();

    Verification verify(
            Map<String, Object> existing,
            Map<String, Object> candidate,
            double distanceMeters);

    record Verification(boolean samePlace, double confidence) {}
}
