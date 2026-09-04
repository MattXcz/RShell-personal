# Záložní přístup k routeru přes reverzní SSH tunel

Řeší situaci, kdy router čas od času spadne z VPN a potřebuješ se k němu i
tak dostat a znovu ho připojit. Router si sám aktivně drží **odchozí** SSH
spojení na tvůj domácí server, nezávisle na VPN — takže i po výpadku VPN
zůstává tenhle kanál funkční, dokud má router aspoň nějaké připojení k netu.

## Jak to funguje

```
[Router] --(odchozí SSH tunel, port X)--> [Domácí server]

Ty se pak připojíš na domácí server a odtamtud:
ssh -p 2222 root@127.0.0.1  →  fyzicky skončíš na routeru
```

Tunelovací účet na serveru (`routertunnel`) neumí nic jiného než tenhle
jeden port forwardovat — nemá shell, nemůže spouštět příkazy. Skutečný shell
přístup k routeru jde přes routerovo **vlastní** sshd (jeho vlastní
root/admin přihlašovací údaje), ne přes tunelovací účet.

## Nasazení jedním příkazem (po nahrání do vlastního git repa)

Nejdřív nahraj obsah téhle složky do vlastního (klidně privátního) repa na
GitHubu, ať se soubory dají stáhnout přes `raw.githubusercontent.com`.
Nahraď `MattXcz/RShell-personal` v příkazech níže svým repem.

### 1. Na routeru (jako root)

Proměnné se zadávají jako env proměnné před `sh`, `HOME_SERVER_HOST` je
schválně poslední, protože je to jediná povinná a nejčastěji měněná
hodnota:

```bash
curl -fsSL https://raw.githubusercontent.com/MattXcz/RShell-personal/main/install-router.sh \
  | HOME_SERVER_PORT=2222 REMOTE_PORT=2222 HOME_SERVER_HOST=your.home.server sh
```

Skript vygeneruje klíč (pokud ještě neexistuje), nainstaluje a spustí
systemd službu (nebo cron watchdog, pokud systemd chybí) a na konci vypíše
hotový příkaz pro krok 2 i s routerovým veřejným klíčem.

`HOME_SERVER_PORT` a `REMOTE_PORT` mají výchozí hodnotu `2222`, takže je
můžeš i vynechat, pokud ti to vyhovuje:

```bash
curl -fsSL https://raw.githubusercontent.com/MattXcz/RShell-personal/main/install-router.sh \
  | HOME_SERVER_HOST=your.home.server sh
```

### 2. Na domácím serveru (jako root)

Zkopíruj a spusť příkaz, který vypsal krok 1 — vypadá takto:

```bash
curl -fsSL https://raw.githubusercontent.com/MattXcz/RShell-personal/main/server-setup.sh \
  | sudo REMOTE_PORT=2222 bash -s -- "ssh-ed25519 AAAA... router-reverse-tunnel"
```

Vytvoří to omezený účet `routertunnel`, který neumí nic jiného než tenhle
jeden port forwardovat.

### Ruční nasazení (bez git repa)

Pokud nechceš nic hostovat na GitHubu, dá se stejné nastavit i ručně —
postup je v souborech `install-router.sh` a `server-setup.sh` (dají se
spustit i lokálně zkopírované, ne jen přes curl).

### Ověř

Na domácím serveru:
```bash
ssh -p 2222 root@127.0.0.1
```
Měl by ses dostat na router, i když je zrovna VPN dole.

## Bezpečnostní doporučení

- **Neveřejný port** — nepoužívej výchozí čísla, uveď si vlastní.
- **fail2ban** na domácím serveru pro sshd.
- **Jen klíče, žádná hesla** — `PasswordAuthentication no` v sshd_config.
- **GatewayPorts no** (výchozí v setup skriptu) — tunelovaný port je
  dostupný jen z localhostu serveru, ne z internetu. Pokud se chceš k
  routeru dostat i zvenku, připojuj se na domácí server přes jeho vlastní
  VPN/SSH a odtamtud dál na `127.0.0.1:2222`, ne že bys tunelovaný port
  vystavoval veřejně.
- Dedikovaný klíč jen pro tenhle tunel (ne tvůj běžný SSH klíč), aby šel
  snadno a bez dopadu na cokoliv jiného odvolat, kdyby se router někdy
  kompromitoval.
