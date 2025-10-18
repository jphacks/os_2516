package config

import (
	"bufio"
	"errors"
	"fmt"
	"os"
	"strings"
)

// LoadEnvFiles は指定された .env ファイル群を読み込み、環境変数として設定します。
// ファイルが存在しない場合はスキップし、その他のエラーはまとめて返します。
func LoadEnvFiles(paths ...string) error {
	var loadErr error

	for _, path := range paths {
		if strings.TrimSpace(path) == "" {
			continue
		}

		if err := loadEnvFile(path); err != nil {
			if errors.Is(err, os.ErrNotExist) {
				continue
			}
			if loadErr == nil {
				loadErr = fmt.Errorf("load env file %s: %w", path, err)
			} else {
				loadErr = fmt.Errorf("%v; load env file %s: %w", loadErr, path, err)
			}
		}
	}

	return loadErr
}

func loadEnvFile(path string) error {
	file, err := os.Open(path)
	if err != nil {
		return err
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		key, value, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}

		key = strings.TrimSpace(key)
		value = strings.TrimSpace(value)
		value = strings.Trim(value, "\"'")

		if key == "" {
			continue
		}

		if err := os.Setenv(key, value); err != nil {
			return fmt.Errorf("set env %s: %w", key, err)
		}
	}

	if err := scanner.Err(); err != nil {
		return err
	}

	return nil
}
