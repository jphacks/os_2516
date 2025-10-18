package data

import (
    "encoding/json"
    "os"
)

type MagicType struct {
    ID          string `json:"id"`
    Name        string `json:"name"`
    MPCost      int    `json:"mp_cost"`
    Description string `json:"description"`
    Damage      int    `json:"damage"`
    Sound       string `json:"sound"`
}

type MagicTypeList struct {
    MagicTypes []MagicType `json:"magic_types"`
}

func LoadMagicTypes(path string) (*MagicTypeList, error) {
    file, err := os.Open(path)
    if err != nil {
        return nil, err
    }
    defer file.Close()

    var list MagicTypeList
    if err := json.NewDecoder(file).Decode(&list); err != nil {
        return nil, err
    }
    return &list, nil
}
