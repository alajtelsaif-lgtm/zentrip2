package com.zentrip.api;

import java.nio.file.Files;
import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.mock.web.MockMultipartFile;

class ProfilePhotoStorageTest {
    @TempDir
    Path uploadDirectory;

    @Test
    void storesPhotoWithGeneratedNameAndServableUrl() throws Exception {
        ProfilePhotoStorage storage = new ProfilePhotoStorage(uploadDirectory.toString());
        byte[] contents = {1, 2, 3, 4};
        MockMultipartFile photo = new MockMultipartFile(
                "photo", "../../avatar.png", "image/png", contents);

        String photoUrl = storage.store(photo);
        Path savedFile = uploadDirectory.resolve(photoUrl.substring("/uploads/".length()));

        assertTrue(photoUrl.startsWith("/uploads/"));
        assertTrue(savedFile.getFileName().toString().endsWith(".png"));
        assertArrayEquals(contents, Files.readAllBytes(savedFile));
    }
}