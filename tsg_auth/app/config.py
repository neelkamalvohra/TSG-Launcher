from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    database_url: str
    jwt_secret: str
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 60
    refresh_token_expire_days: int = 30
    init_superadmin_username: str = "superadmin"
    init_superadmin_password: str
    init_superadmin_email: str = "superadmin@tsg.local"
    # Password policy
    password_expiry_days: int = 90
    inactivity_disable_days: int = 30
    # SMTP (Gmail) for password reset emails
    smtp_host: str = "smtp.gmail.com"
    smtp_port: int = 587
    smtp_username: str = "Neelkamal.Vohra@gmail.com"
    smtp_password: str = "CHANGE_ME_gmail_app_password"
    smtp_from_name: str = "TSG Auth"

    model_config = SettingsConfigDict(env_prefix="TSG_AUTH_", env_file=".env")


settings = Settings()
