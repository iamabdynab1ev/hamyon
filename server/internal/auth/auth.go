package auth

import (
	"context"
	"crypto/rand"
	"encoding/base32"
	"fmt"
	"strings"
	"time"

	"cashew-server/internal/domain"

	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"
)

type Claims struct {
	FamilyID string      `json:"fid"`
	Role     domain.Role `json:"role"`
	jwt.RegisteredClaims
}

type Identity struct {
	UserID   string
	FamilyID string
	Role     domain.Role
}

func (i Identity) IsOwner() bool { return i.Role == domain.RoleOwner }

func HashPassword(password string) (string, error) {
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return "", fmt.Errorf("auth hash password: %w", err)
	}
	return string(hash), nil
}

func CheckPassword(hash, password string) bool {
	return bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)) == nil
}

func IssueToken(secret []byte, user domain.User, ttl time.Duration) (string, time.Time, error) {
	expiresAt := time.Now().Add(ttl)
	claims := Claims{
		FamilyID: user.FamilyID,
		Role:     user.Role,
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   user.ID,
			ExpiresAt: jwt.NewNumericDate(expiresAt),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
		},
	}

	signed, err := jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString(secret)
	if err != nil {
		return "", time.Time{}, fmt.Errorf("auth issue token: %w", err)
	}
	return signed, expiresAt, nil
}

func ParseToken(secret []byte, token string) (Identity, error) {
	claims := &Claims{}
	parsed, err := jwt.ParseWithClaims(token, claims, func(t *jwt.Token) (any, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method %v", t.Header["alg"])
		}
		return secret, nil
	}, jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}))
	if err != nil || !parsed.Valid {
		return Identity{}, domain.ErrForbidden
	}

	return Identity{
		UserID:   claims.Subject,
		FamilyID: claims.FamilyID,
		Role:     claims.Role,
	}, nil
}

// GenerateJoinCode делает короткий код, который владелец диктует родным, чтобы
// они присоединились к семье. Алфавит base32 без похожих друг на друга символов.
func GenerateJoinCode() (string, error) {
	raw := make([]byte, 5)
	if _, err := rand.Read(raw); err != nil {
		return "", fmt.Errorf("auth generate join code: %w", err)
	}
	encoder := base32.NewEncoding("ABCDEFGHJKLMNPQRSTUVWXYZ23456789").WithPadding(base32.NoPadding)
	return encoder.EncodeToString(raw), nil
}

func NormalizeLogin(login string) string {
	return strings.ToLower(strings.TrimSpace(login))
}

type identityKey struct{}

func WithIdentity(ctx context.Context, identity Identity) context.Context {
	return context.WithValue(ctx, identityKey{}, identity)
}

func IdentityFrom(ctx context.Context) (Identity, bool) {
	identity, ok := ctx.Value(identityKey{}).(Identity)
	return identity, ok
}
