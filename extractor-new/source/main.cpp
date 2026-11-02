/*
 * Dependencies:
 * - libsodium
 * - msgpack-c
 */

#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <map>
#include <memory>
#include <filesystem>
#include <algorithm>
#include <iomanip>
#include <cstring>
#include <stdexcept>
#include <optional>
#include <chrono>
#include <sstream>

#include <sodium.h>
#include <msgpack.hpp>

namespace fs = std::filesystem;
using Bytes = std::vector<unsigned char>;

// ==================== Configuration & Logging ====================

struct Config {
    bool verbose = false;
    bool list_only = false;
    std::string infile;
    std::string destdir = ".";
    std::optional<int> keytype;
    std::vector<std::string> files;
};

class Logger {
public:
    explicit Logger(bool verbose) : verbose_(verbose) {}

    void info(const std::string& msg) const {
        std::cout << "[INFO] " << msg << std::endl;
    }

    void debug(const std::string& msg) const {
        if (verbose_) {
            std::cout << "[DEBUG] " << msg << std::endl;
        }
    }

    void error(const std::string& msg) const {
        std::cerr << "[ERROR] " << msg << std::endl;
    }

private:
    bool verbose_;
};

// ==================== Key Management ====================

struct KeyPair {
    Bytes public_key;
    Bytes subkey;
};

class KeyStore {
public:
    KeyStore() {
        init_keys();
    }

    const KeyPair& get_key(int type) const {
        auto it = keys_.find(type);
        if (it == keys_.end()) {
            throw std::runtime_error("Invalid keytype index");
        }
        return it->second;
    }

    std::string get_name(int type) const {
        static const std::map<int, std::string> names = {
            {0, "SYSTEM"}, {1, "NANO"}, {2, "JSON"}, {3, "SPK"},
            {4, "SYNOMIBCOLLECTOR"}, {5, "SSDB"}, {6, "AUTOUPDATE"},
            {7, "FIRMWARE"}, {8, "DEV"}, {9, "WEDJAT"},
            {10, "DSM_SUPPORT_PATCH"}, {11, "SMALL"}
        };
        auto it = names.find(type);
        return (it != names.end()) ? it->second : "UNKNOWN";
    }

    bool has_key(int type) const {
        return keys_.count(type);
    }

    static Bytes hex_to_bytes(const std::string& hex) {
        Bytes bytes;
        for (unsigned int i = 0; i < hex.length(); i += 2) {
            std::string byteString = hex.substr(i, 2);
            unsigned char byte = (unsigned char)strtol(byteString.c_str(), NULL, 16);
            bytes.push_back(byte);
        }
        return bytes;
    }

private:
    std::map<int, KeyPair> keys_;

    void init_keys() {
        keys_[0] = {hex_to_bytes("64FABA48FEEC6C8A2484D2489A11418A0E980317A9CC6B392F1041925B293FE0"), hex_to_bytes("078A7529A07A998CFFADB87D7378993B7D9CCFA7171F5C47F150838A6A7CAF61")};
        keys_[1] = {hex_to_bytes("64FABA48FEEC6C8A2484D2489A11418A0E980317A9CC6B392F1041925B293FE0"), hex_to_bytes("9C388F52826A10B9838FF743F6B66B30CDCB1247ADBE566275F1F5A69F8F26FB")};
        keys_[2] = {hex_to_bytes("95BBD04B3903C199026BE07AB14FBCF41863AC32251B4FF11774FA0BD98305A7"), hex_to_bytes("078A7529A07A998CFFADB87D7378993B7D9CCFA7171F5C47F150838A6A7CAF61")};
        keys_[3] = {hex_to_bytes("FECAA2DD065A86A68E5FE86BA34CD8481590A79FA2C29A7D69F25A3B3BFAA19E"), hex_to_bytes("CF0D8D6ECB95EF97D0AC6A7021D99124C699808CF2CC5157DFEA5EBF15C805E7")};
        keys_[4] = {hex_to_bytes("2B6D761B5786FF65D16C50E551EA11F2AD4E61E344A8272CBDC65A9AD0619AE8"), hex_to_bytes("977D1511DB2B7F7C7158FC717C2E7AC4952703748A884D731FF24F4AFF7E3038")};
        keys_[5] = {hex_to_bytes("B8A31F0FDCDAB36415BAC54B2872E1223080CB7C58D0E2B2C9F528523E9E3FB0"), hex_to_bytes("8E1BDA67B47F2892C656FB542FDD668A389C718A8ADE429E5ECF4D66D36483AA")};
        keys_[6] = {hex_to_bytes("757E037E512E20FAEDB7218E2AD75AD55244741E54A31049132F4789A3A66C31"), hex_to_bytes("6A8360CE72E41347771A06F6C1FEA03CDF0E56994D244EB3FE99DC478086AE04")};
        keys_[7] = {hex_to_bytes("0169F56624F5BAB7B709D0557CE9BFBB12C25D900CA9C21663E20C8DD31A1AA2"), hex_to_bytes("9AD877F649993B05ADF64D13CE5CFB84EA65105F7B48C3ED428B1769B6456DD4")};
        keys_[8] = {hex_to_bytes("50CE5E3E525E1E144C1A749FFF7A79C2E2FFB322DF85093FC1226530CC0EC59C"), hex_to_bytes("078A7529A07A998CFFADB87D7378993B7D9CCFA7171F5C47F150838A6A7CAF61")};
        keys_[9] = {hex_to_bytes("9A0A314963458EDFAE530BB2991B66A26B23A276444D29215A94C5CE85EE61A0"), hex_to_bytes("25F962A7D4AD6A0C4538989860F1150FB62FC902399DBEE62DBF080AED885990")};
        keys_[10] = {hex_to_bytes("64FABA48FEEC6C8A2484D2489A11418A0E980317A9CC6B392F1041925B293FE0"), hex_to_bytes("078A7529A07A998CFFADB87D7378993B7D9CCFA7171F5C47F150838A6A7CAF61")};
        keys_[11] = {hex_to_bytes("64FABA48FEEC6C8A2484D2489A11418A0E980317A9CC6B392F1041925B293FE0"), hex_to_bytes("078A7529A07A998CFFADB87D7378993B7D9CCFA7171F5C47F150838A6A7CAF61")};
    }
};

// ==================== TAR Definitions ====================

#pragma pack(push, 1)
struct archive_entry_header {
    char name[100];
    char mode[8];
    char uid[8];
    char gid[8];
    char size[12];
    char mtime[12];
    char checksum[8];
    char typeflag[1];
    char linkname[100];
    char magic[6];
};

struct gnu_sparse {
    char offset[12];
    char numbytes[12];
};

struct archive_entry_header_gnutar {
    char name[100];
    char mode[8];
    char uid[8];
    char gid[8];
    char size[12];
    char mtime[12];
    char checksum[8];
    char typeflag[1];
    char linkname[100];
    char magic[8];
    char uname[32];
    char gname[32];
    char devmajor[8];
    char devminor[8];
    char atime[12];
    char ctime[12];
    char offset[12];
    char longnames[4];
    char unused[1];
    struct gnu_sparse sparse[4];
    char isextended[1];
    char realsize[12];
};
#pragma pack(pop)

// ==================== Utility Functions ====================

long long atol_oct(const char* s, size_t size) {
    std::string str(s, size);
    str.erase(std::remove(str.begin(), str.end(), '\0'), str.end());
    str.erase(std::remove(str.begin(), str.end(), ' '), str.end());
    if (str.empty()) return 0;
    try {
        return std::stoll(str, nullptr, 8);
    } catch (...) {
        return 0;
    }
}

// ==================== Core Decryption Class ====================

class PatDecryptor {
public:
    static constexpr int TAR_BLOCKSIZE = 0x200;
    static constexpr int CHACHA20_HEADERSIZE = 24;
    static constexpr int MAGIC_VALUE = 0xADBEEF;
    static constexpr int MAGIC_OFFSET = 0;
    static constexpr int MSGPACK_HEADER_LENGTH_OFFSET = 4;
    static constexpr int SIGNATURE_LENGTH = 64;
    static constexpr int CHACHA20_CHUNK_SIZE = 0x400000;
    static constexpr int ENCRYPTED_HEADER_SIZE = 0x193;

    struct TarInfo {
        std::string name;
        long long size;
        long long mtime;
        int mode;
        int uid;
        int gid;
    };

    struct Entry {
        long long size;
        long long entry_offset;
        long long archive_offset;
        TarInfo header;
        Bytes data;
    };

    struct MessageBlock {
        long long size;
        Bytes hash;
    };

    PatDecryptor(std::ifstream& archive, const Config& config, const KeyStore& keyStore, const Logger& logger)
        : archive_(archive), config_(config), keyStore_(keyStore), logger_(logger) {
        
        if (sodium_init() < 0) {
            throw std::runtime_error("libsodium initialization failed");
        }
        validate_and_init();
    }

    void unpack() {
        if (config_.list_only) {
            list_files();
            return;
        }

        fs::create_directories(config_.destdir);
        fs::path dest_root_canonical;
        try {
            dest_root_canonical = fs::weakly_canonical(fs::absolute(config_.destdir));
        } catch (const std::exception& e) {
            throw std::runtime_error("Failed to resolve destination directory: " + std::string(e.what()));
        }

        int failed = 0;
        int extracted = 0;

        std::map<std::string, Entry> entries_to_extract;
        if (!config_.files.empty()) {
            for (const auto& f : config_.files) {
                if (entries_.count(f)) {
                    entries_to_extract[f] = entries_[f];
                } else {
                    logger_.error("File not found in archive: " + f);
                    ++failed;
                }
            }
            if (entries_to_extract.empty()) {
                throw std::runtime_error("No matching files found");
            }
        } else {
            entries_to_extract = entries_;
        }

        for (auto& [name, entry] : entries_to_extract) {
            fs::path rel_path = fs::path(name).relative_path();
            fs::path filepath = dest_root_canonical / rel_path;
            
            fs::path filepath_canonical;
            try {
                filepath_canonical = fs::weakly_canonical(filepath);
            } catch (const std::exception& e) {
                logger_.error("Skipping invalid path " + name + ": " + e.what());
                ++failed;
                continue;
            }

            std::string p_str = filepath_canonical.generic_string();
            std::string r_str = dest_root_canonical.generic_string();

            if (r_str.back() != '/') r_str += '/';
            if (p_str.length() < r_str.length() && p_str != dest_root_canonical.generic_string()) {
                 logger_.error("Security warning: Path traversal attempt detected. Skipping " + name);
                 ++failed;
                 continue;
            }
            
            if (p_str != dest_root_canonical.generic_string()) {
                if (p_str.find(r_str) != 0) {
                    logger_.error("Security warning: Path traversal attempt detected. Skipping " + name + " -> " + p_str);
                    ++failed;
                    continue;
                }
            }

            fs::create_directories(filepath.parent_path());

            bool is_dir = (name.back() == '/' || (entry.header.mode & 0170000) == 0040000);

            if (is_dir) {
                fs::create_directories(filepath);
            } else {
                Bytes data;
                if (!entry.data.empty()) {
                    data = entry.data;
                } else {
                    logger_.debug("Re-decrypting " + name + " (offset " + std::to_string(entry.archive_offset) + ")");
                    data = decrypt_tar_entry(entry.archive_offset, entry.size);
                }

                if ((long long)data.size() != entry.size) {
                    logger_.error("Failed to decrypt " + name);
                    ++failed;
                    continue;
                }

                std::ofstream outfile(filepath, std::ios::binary);
                outfile.write(reinterpret_cast<const char*>(data.data()), data.size());
                outfile.close();
                if (!outfile) {
                    logger_.error("Failed to write " + filepath.string());
                    ++failed;
                    continue;
                }
                logger_.debug("Extracted: " + filepath.string() + " [" + std::to_string(data.size()) + " bytes]");
            }
            ++extracted;
            
            try {
                auto mtime = (std::time_t)entry.header.mtime;
                auto sys_time = std::chrono::system_clock::from_time_t(mtime);
                auto time_diff = sys_time - std::chrono::system_clock::now();
                auto file_time = std::filesystem::file_time_type::clock::now() + time_diff;
                fs::last_write_time(filepath, file_time);
            } catch (const std::exception& e) {
                logger_.error("Failed to set mtime for " + name + ": " + e.what());
            }
        }
        logger_.info("Successfully extracted " + std::to_string(extracted) + " files");
        if (failed > 0) {
            throw std::runtime_error(std::to_string(failed) + " file(s) could not be extracted");
        }
    }

private:
    std::ifstream& archive_;
    const Config& config_;
    const KeyStore& keyStore_;
    const Logger& logger_;

    std::optional<int> detected_keytype_;
    std::map<std::string, Entry> entries_;
    long long encrypted_tar_offset_ = 0;
    Bytes msgpack_header_;
    std::vector<MessageBlock> messageblocks_;
    Bytes chacha20_key_;

    void read_exact(char* buffer, size_t size, const std::string& desc) {
        archive_.read(buffer, size);
        if (archive_.gcount() != static_cast<std::streamsize>(size)) {
             throw std::runtime_error("Unexpected EOF while reading " + desc);
        }
    }

    long long remaining_bytes() {
        const std::streampos pos = archive_.tellg();
        archive_.seekg(0, std::ios::end);
        const long long remaining = archive_.tellg() - pos;
        archive_.seekg(pos);
        return remaining;
    }

    void validate_and_init() {
        verify_magic();

        if (config_.keytype.has_value()) {
            try {
                verify_signature(config_.keytype.value());
                detected_keytype_ = config_.keytype.value();
            } catch (const std::exception& e) {
                throw std::runtime_error(std::string("Invalid keytype: ") + e.what());
            }
        } else {
            auto_detect_keytype();
        }

        derive_key();
        verify_msgpack_blocks();
        parse();
    }

    void verify_magic() {
        archive_.seekg(MAGIC_OFFSET);
        unsigned char magic_buf[4];
        read_exact((char*)magic_buf, 4, "magic");
        
        uint32_t magic = (magic_buf[0] << 24) | (magic_buf[1] << 16) | (magic_buf[2] << 8) | magic_buf[3];
        magic &= 0xFFFFFF;

        if (magic != MAGIC_VALUE) {
            throw std::runtime_error("Invalid magic");
        }
        logger_.debug("Magic verified");
    }

    void auto_detect_keytype() {
        for (int k = 0; k < 12; ++k) {
            try {
                archive_.seekg(MSGPACK_HEADER_LENGTH_OFFSET);
                msgpack_header_.clear();
                messageblocks_.clear();

                verify_signature(k);
                detected_keytype_ = k;
                
                try {
                    derive_key();
                    verify_msgpack_blocks();
                } catch (...) {
                    continue;
                }

                if (candidate_decrypts_to_valid_tar()) {
                    logger_.info("Detected keytype: " + keyStore_.get_name(k) + " (" + std::to_string(k) + ")");
                    return;
                }
            } catch (...) {
                // Ignore
            }
        }
        throw std::runtime_error("Failed to detect valid keytype");
    }

    void verify_signature(int keytype) {
        const KeyPair& keys = keyStore_.get_key(keytype);
        archive_.seekg(MSGPACK_HEADER_LENGTH_OFFSET);

        uint32_t header_length = 0;
        read_exact((char*)&header_length, 4, "msgpack header length");

        // The header is not authenticated yet: never allocate more than the file can hold
        if (header_length > remaining_bytes() - SIGNATURE_LENGTH) {
            throw std::runtime_error("Invalid msgpack header length");
        }

        msgpack_header_.resize(header_length);
        read_exact((char*)msgpack_header_.data(), header_length, "msgpack header");

        Bytes signature(SIGNATURE_LENGTH);
        read_exact((char*)signature.data(), SIGNATURE_LENGTH, "signature");

        if (crypto_sign_verify_detached(signature.data(), msgpack_header_.data(), msgpack_header_.size(), keys.public_key.data()) != 0) {
            throw std::runtime_error("Signature verification failed");
        }

        encrypted_tar_offset_ = archive_.tellg();
        logger_.debug("Signature verified for " + keyStore_.get_name(keytype));
    }

    void derive_key() {
        const KeyPair& keys = keyStore_.get_key(detected_keytype_.value());
        
        msgpack::object_handle oh = msgpack::unpack((const char*)msgpack_header_.data(), msgpack_header_.size());
        msgpack::object obj = oh.get();

        std::vector<msgpack::object> messages;
        obj.convert(messages);

        if (messages.size() < 2) throw std::runtime_error("Invalid msgpack structure");

        Bytes msgpack_obj_bytes;
        messages[0].convert(msgpack_obj_bytes);
        
        std::reverse(msgpack_obj_bytes.begin(), msgpack_obj_bytes.end());

        if (msgpack_obj_bytes.size() < 0x10) throw std::runtime_error("msgpack_obj too short");

        uint64_t subkey_id_be;
        std::memcpy(&subkey_id_be, &msgpack_obj_bytes[0x8], 8);

        uint64_t subkey_id = 0;
        unsigned char* p = (unsigned char*)&subkey_id_be;
        subkey_id = ((uint64_t)p[0] << 56) | ((uint64_t)p[1] << 48) | ((uint64_t)p[2] << 40) | ((uint64_t)p[3] << 32) |
                    ((uint64_t)p[4] << 24) | ((uint64_t)p[5] << 16) | ((uint64_t)p[6] << 8)  | (uint64_t)p[7];

        Bytes ctx_slice(msgpack_obj_bytes.begin() + 1, msgpack_obj_bytes.begin() + 8);
        std::reverse(ctx_slice.begin(), ctx_slice.end());
        ctx_slice.push_back(0x00);
        
        char ctx[8];
        std::memcpy(ctx, ctx_slice.data(), 8);

        chacha20_key_.resize(crypto_kdf_KEYBYTES);
        if (crypto_kdf_derive_from_key(chacha20_key_.data(), chacha20_key_.size(), subkey_id, ctx, keys.subkey.data()) != 0) {
            throw std::runtime_error("Key derivation failed");
        }

        logger_.debug("ChaCha20 key derived");
                
        messageblocks_.clear();

        std::vector<msgpack::object> blocks_raw;
        messages[1].convert(blocks_raw);
        
        messageblocks_.push_back({0, {}}); 

        for (auto& b : blocks_raw) {
            std::vector<msgpack::object> item;
            b.convert(item);
            long long sz = 0;
            Bytes h;
            if (item.size() > 0) item[0].convert(sz);
            if (item.size() > 1) item[1].convert(h);
            messageblocks_.push_back({sz, h});
        }
    }

    void verify_msgpack_blocks() {
        archive_.seekg(encrypted_tar_offset_);
        
        for (size_t i = 1; i < messageblocks_.size(); ++i) {
            long long size = messageblocks_[i].size;
            Bytes expected_hash = messageblocks_[i].hash;
            
            if (size < 0 || size > remaining_bytes()) {
                throw std::runtime_error("Invalid msgpack block size");
            }

            Bytes enc_entry(size);
            read_exact((char*)enc_entry.data(), size, "encrypted entry");
            
            unsigned char hash[crypto_generichash_blake2b_BYTES];
            crypto_generichash_blake2b(hash, sizeof(hash), enc_entry.data(), size, NULL, 0);
                        
            if (expected_hash.size() < sizeof(hash) || std::memcmp(hash, expected_hash.data(), sizeof(hash)) != 0) {
                 throw std::runtime_error("msgpack block hash mismatch");
            }
        }
        logger_.debug("All msgpack blocks verified");
    }

    struct BlockPos {
        size_t idx;
        long long offset;
        long long size;
    };

    std::vector<BlockPos> compute_messageblock_positions() {
        std::vector<BlockPos> positions;
        long long pos = encrypted_tar_offset_;
        for (size_t i = 0; i < messageblocks_.size(); ++i) {
            positions.push_back({i, pos, messageblocks_[i].size});
            pos += messageblocks_[i].size;
        }
        return positions;
    }

    bool candidate_decrypts_to_valid_tar() {
        auto positions = compute_messageblock_positions();
        for (size_t i = 1; i < positions.size(); ++i) {
            if (positions[i].size == 0) continue;
            
            archive_.seekg(positions[i].offset);
            
            Bytes chacha_header(CHACHA20_HEADERSIZE);
            archive_.read((char*)chacha_header.data(), CHACHA20_HEADERSIZE);
            if (archive_.gcount() != CHACHA20_HEADERSIZE) return false;

            crypto_secretstream_xchacha20poly1305_state state;
            if (crypto_secretstream_xchacha20poly1305_init_pull(&state, chacha_header.data(), chacha20_key_.data()) != 0) {
                return false;
            }

            Bytes enc_header(ENCRYPTED_HEADER_SIZE);
            archive_.read((char*)enc_header.data(), ENCRYPTED_HEADER_SIZE);
            
            Bytes decrypted(enc_header.size() - crypto_secretstream_xchacha20poly1305_ABYTES);
            unsigned long long mlen;
            if (crypto_secretstream_xchacha20poly1305_pull(&state, decrypted.data(), &mlen, NULL, enc_header.data(), enc_header.size(), NULL, 0) != 0) {
                return false;
            }

            if (decrypted.size() >= 263) {
                if (std::memcmp(decrypted.data() + 257, "ustar", 5) == 0) {
                    return true;
                }
            }
        }
        return false;
    }

    void parse() {
        archive_.seekg(encrypted_tar_offset_);
        decrypt_tar_headers();
        
        if (!config_.list_only) {
            for (auto& [name, entry] : entries_) {
                entry.data = decrypt_tar_entry(entry.archive_offset, entry.size);
            }
        }
    }

    void decrypt_tar_headers() {
        auto positions = compute_messageblock_positions();
        for (const auto& pos : positions) {
            if (pos.idx == 0) continue; 
            
            archive_.seekg(pos.offset);
            
            Bytes chacha_header(CHACHA20_HEADERSIZE);
            if (!archive_.read((char*)chacha_header.data(), CHACHA20_HEADERSIZE)) continue;

            crypto_secretstream_xchacha20poly1305_state state;
            if (crypto_secretstream_xchacha20poly1305_init_pull(&state, chacha_header.data(), chacha20_key_.data()) != 0) continue;

            Bytes enc_header(ENCRYPTED_HEADER_SIZE);
            archive_.read((char*)enc_header.data(), ENCRYPTED_HEADER_SIZE);

            Bytes decrypted(enc_header.size() - crypto_secretstream_xchacha20poly1305_ABYTES);
            unsigned long long mlen;
            if (crypto_secretstream_xchacha20poly1305_pull(&state, decrypted.data(), &mlen, NULL, enc_header.data(), enc_header.size(), NULL, 0) != 0) continue;

            process_tar_header(decrypted, pos.offset, pos.offset - encrypted_tar_offset_);
        }
    }

    void process_tar_header(Bytes& decrypted, long long offset, long long entry_offset) {
        if (decrypted.size() < sizeof(archive_entry_header)) return;

        archive_entry_header* header = (archive_entry_header*)decrypted.data();
        
        std::string magic(header->magic, 6);
        if (magic.find("ustar") == 0) {
             if (decrypted.size() >= sizeof(archive_entry_header_gnutar)) {
             }
        } else {
            return;
        }

        TarInfo info;
        info.name = std::string(header->name, strnlen(header->name, sizeof(header->name)));
        info.size = atol_oct(header->size, 12);
        info.mtime = atol_oct(header->mtime, 12);
        info.mode = (int)atol_oct(header->mode, 8);
        info.uid = (int)atol_oct(header->uid, 8);
        info.gid = (int)atol_oct(header->gid, 8);

        entries_[info.name] = {info.size, entry_offset, offset, info, {}};
    }

    Bytes decrypt_tar_entry(long long entry_offset, long long entry_size) {
        
        archive_.seekg(entry_offset + TAR_BLOCKSIZE);
        
        Bytes chacha_header(CHACHA20_HEADERSIZE);
        read_exact((char*)chacha_header.data(), CHACHA20_HEADERSIZE, "entry chacha header");

        logger_.debug("Decrypting entry at offset " + std::to_string(entry_offset) + ", size " + std::to_string(entry_size));

        crypto_secretstream_xchacha20poly1305_state state;
        if (crypto_secretstream_xchacha20poly1305_init_pull(&state, chacha_header.data(), chacha20_key_.data()) != 0) {
            logger_.error("Failed to init chacha for entry");
            return {};
        }

        Bytes result;
        long long bytes_remaining = entry_size;
        
        while (bytes_remaining > 0) {
            long long chunk_size = std::min((long long)CHACHA20_CHUNK_SIZE, bytes_remaining) + crypto_secretstream_xchacha20poly1305_ABYTES;
            Bytes encrypted_chunk(chunk_size);
            read_exact((char*)encrypted_chunk.data(), chunk_size, "entry chunk");

            Bytes decrypted(chunk_size - crypto_secretstream_xchacha20poly1305_ABYTES);
            unsigned long long mlen;
            if (crypto_secretstream_xchacha20poly1305_pull(&state, decrypted.data(), &mlen, NULL, encrypted_chunk.data(), encrypted_chunk.size(), NULL, 0) != 0) {
                logger_.error("Failed to decrypt entry chunk. Offset: " + std::to_string(entry_offset));
                break;
            }
            
            result.insert(result.end(), decrypted.begin(), decrypted.begin() + mlen);
            bytes_remaining -= mlen;
        }
        
        return result;
    }

    void list_files() {
        logger_.info("Listing files in archive:");
        for (const auto& [name, entry] : entries_) {
            std::cout << format_mode(entry.header.mode) << " "
                      << std::setw(5) << entry.header.uid << " "
                      << std::setw(5) << entry.header.gid << " "
                      << std::setw(10) << entry.header.size << " "
                      << format_time(entry.header.mtime) << " "
                      << name << std::endl;
        }
    }

    std::string format_mode(int mode) {
        std::string s = "----------";
        if ((mode & 0170000) == 0040000) s[0] = 'd';
        if (mode & 0400) s[1] = 'r';
        if (mode & 0200) s[2] = 'w';
        if (mode & 0100) s[3] = 'x';
        if (mode & 0040) s[4] = 'r';
        if (mode & 0020) s[5] = 'w';
        if (mode & 0010) s[6] = 'x';
        if (mode & 0004) s[7] = 'r';
        if (mode & 0002) s[8] = 'w';
        if (mode & 0001) s[9] = 'x';
        return s;
    }

    std::string format_time(long long mtime) {
        std::time_t t = (std::time_t)mtime;
        std::tm tm{};
#ifdef _WIN32
        const bool valid = localtime_s(&tm, &t) == 0;
#else
        const bool valid = localtime_r(&t, &tm) != nullptr;
#endif
        if (!valid) return "0000-00-00 00:00";
        std::ostringstream oss;
        oss << std::put_time(&tm, "%Y-%m-%d %H:%M");
        return oss.str();
    }
};

// ==================== Main ====================

int main(int argc, char* argv[]) {
    Config config;

    std::cout << "SynoXtract v1.1 - pRT" << std::endl;
    std::cout << "-----------------------" << std::endl;

    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "-h" || arg == "--help") {
            std::cout << "Decrypt and extract Synology archive files\n"
                      << "Usage: synoxtract -i <file.pat> [options]\n\n"
                      << "Options:\n"
                      << "  -h, --help            Show this help\n"
                      << "  -i, --infile FILE     Input .pat/.spk file\n"
                      << "  -d, --destdir DIR     Output directory (default: .)\n"
                      << "  -f, --files FILES...  Specific files to extract\n"
                      << "  -l, --list            List files without extracting\n"
                      << "  -k, --keytype TYPE    Keytype (0-11)\n"
                      << "  -v, --verbose         Enable verbose logging" << std::endl;
            return 0;
        } else if (arg == "-i" || arg == "--infile") {
            if (i + 1 < argc) config.infile = argv[++i];
        } else if (arg == "-d" || arg == "--destdir") {
            if (i + 1 < argc) config.destdir = argv[++i];
        } else if (arg == "-k" || arg == "--keytype") {
            if (i + 1 < argc) {
                try {
                    config.keytype = std::stoi(argv[++i]);
                } catch (const std::exception&) {
                    std::cerr << "Error: Invalid keytype: " << argv[i] << std::endl;
                    return 1;
                }
            }
        } else if (arg == "-v" || arg == "--verbose") {
            config.verbose = true;
        } else if (arg == "-l" || arg == "--list") {
            config.list_only = true;
        } else if (arg == "-f" || arg == "--files") {
            while (i + 1 < argc && argv[i+1][0] != '-') {
                config.files.push_back(argv[++i]);
            }
        }
    }

    if (config.infile.empty()) {
        std::cerr << "Error: No input file specified. Use -i <file>." << std::endl;
        return 1;
    }

    try {
        Logger logger(config.verbose);
        KeyStore keyStore;
        
        std::ifstream archive(config.infile, std::ios::binary);
        if (!archive) {
            throw std::runtime_error("Failed to open file: " + config.infile);
        }

        PatDecryptor decryptor(archive, config, keyStore, logger);
        decryptor.unpack();

    } catch (const std::exception& e) {
        std::cerr << "Fatal error: " << e.what() << std::endl;
        return 1;
    }

    return 0;
}
