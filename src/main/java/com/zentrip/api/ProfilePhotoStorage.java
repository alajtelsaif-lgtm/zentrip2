package com.zentrip.api;

import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.Locale;
import java.util.UUID;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.server.ResponseStatusException;

@Component
public class ProfilePhotoStorage {
    private static final long MAX_SIZE_BYTES = 5 * 1024 * 1024;

    private final Path uploadDirectory;

    public ProfilePhotoStorage(@Value("${app.upload-dir:uploads}") String uploadDirectory) {
        this.uploadDirectory = Path.of(uploadDirectory).toAbsolutePath().normalize();
    }

    public String store(MultipartFile photo) {
        if (photo == null || photo.isEmpty()) return null;
        if (photo.getSize() > MAX_SIZE_BYTES) {
            throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY, "Image must be 5 MB or smaller");
        }

        String extension = switch (String.valueOf(photo.getContentType()).toLowerCase(Locale.ROOT)) {
            case "image/jpeg", "image/jpg" -> ".jpg";
            case "image/png" -> ".png";
            case "image/webp" -> ".webp";
            default -> throw new ResponseStatusException(
                    HttpStatus.UNPROCESSABLE_ENTITY, "Image must be JPEG, PNG, or WebP");
        };

        String filename = UUID.randomUUID() + extension;
        try (InputStream input = photo.getInputStream()) {
            Files.createDirectories(uploadDirectory);
            Files.copy(input, uploadDirectory.resolve(filename), StandardCopyOption.REPLACE_EXISTING);
            return "/uploads/" + filename;
        } catch (IOException exception) {
            throw new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR, "Unable to store image");
        }
    }
}