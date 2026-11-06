# Persona

Persona is a personalised AI news aggregator with no user interface: people talk to a chatbot to create an account, choose their topics and a delivery time, and receive a daily newsletter by email. Everything is built with [n8n](https://n8n.io) workflows, stored in this repository as JSON files.

This guide installs Persona on your own computer, from scratch. Follow the steps in order; each one ends with a check so you know it worked. Allow about 30 minutes the first time.

## What you get

| Workflow | Runs | What it does |
| --- | --- | --- |
| Chat | when someone writes in the chat | AI agent: sign up, log in, profile, send the newsletter now, unsubscribe, export or delete the account |
| News Fetch | every hour | reads 5 RSS feeds and Hacker News, stores new articles |
| News Classify | after News Fetch | Gemini writes a short summary and picks categories for each new article |
| Newsletter Scheduler | every 15 minutes | sends the newsletter to every user whose delivery time has come, in their time zone |
| Newsletter Build / Send | when called | picks the best articles for one user, writes the newsletter in their language, emails it |
| Unsubscribe | from the link in each email | signed one-click unsubscribe page |
| Data Retention | every night at 3am | deletes articles older than 30 days |
| Error Handler | when an automatic workflow fails | emails you an alert |
| Auth - … | when called | accounts, sessions, email verification (used by the chat) |
| Setup DB | once, by hand | creates the data tables |

## 1. Install the tools

You need **Docker**, **git**, **make** and **openssl**. Pick your system:

<details>
<summary><b>macOS</b></summary>

1. Install [Docker Desktop for Mac](https://docs.docker.com/desktop/setup/install/mac-install/) and open it once (the whale icon must appear in the menu bar).
2. Install the command line tools (they include `git` and `make`), in the Terminal app:
   ```bash
   xcode-select --install
   ```
3. `openssl` is already installed.
</details>

<details>
<summary><b>Windows</b></summary>

The commands of this guide need a Linux terminal: use WSL (Windows Subsystem for Linux).

1. Open **PowerShell as administrator** and run `wsl --install`, then restart the computer. An **Ubuntu** terminal is now available in the Start menu: open it and choose a user name and password.
2. Install [Docker Desktop for Windows](https://docs.docker.com/desktop/setup/install/windows-install/). In Docker Desktop, open **Settings → Resources → WSL integration** and turn on **Ubuntu**.
3. In the **Ubuntu** terminal:
   ```bash
   sudo apt update && sudo apt install -y git make openssl
   ```
4. Run **every command of this guide in the Ubuntu terminal**, and clone the project inside it (for example in `~/`), not in `C:\`.
</details>

<details>
<summary><b>Linux (Ubuntu / Debian)</b></summary>

1. Install [Docker Engine](https://docs.docker.com/engine/install/) with the **compose plugin**, then allow your user to run Docker and log out and in again:
   ```bash
   sudo usermod -aG docker $USER
   ```
2. Install the other tools:
   ```bash
   sudo apt update && sudo apt install -y git make openssl
   ```
</details>

**Check:** each of these commands prints a version, not an error. Docker must be running.
```bash
docker --version
docker compose version
git --version
make --version
openssl version
```

## 2. Get the project

```bash
git clone https://github.com/EpitechBachelorPromo2028/B-AIA-300-TLS-3-1-persona-1.git persona
cd persona
```

Every command below is run from this `persona` folder.

## 3. Start n8n

```bash
make up
```

The first time, this creates your `.env` file (with a random `N8N_ENCRYPTION_KEY`), downloads n8n (a few minutes) and starts it.

**Check:** open http://localhost:5678. n8n asks you to create an owner account: fill in an email, a name and a password. This account only exists on your computer.

> If the page does not open, wait 30 seconds and refresh. Still nothing: run `make logs` to see what n8n is doing (Ctrl+C to quit). The port 5678 must not be used by another program.

## 4. Fill in your secrets (`.env`)

Open the `.env` file of the project in a text editor. It contains one line per setting. Fill in each value as explained below, then save the file.

| Variable | What it is | Example |
| --- | --- | --- |
| `N8N_ENCRYPTION_KEY` | Encrypts the secrets stored by n8n. Already filled in by `make up`. | `7e1d30…` |
| `WEBHOOK_URL` | Address of n8n. Keep the default. | `http://localhost:5678/` |
| `SMTP_HOST` | Mail server that sends the emails. | `smtp.gmail.com` |
| `SMTP_PORT` | Port of the mail server. | `465` |
| `SMTP_USER` | Email address that sends the emails. | `persona.newsletter@gmail.com` |
| `SMTP_PASSWORD` | App password of that address (not its normal password). | `"abcd efgh ijkl mnop"` |
| `GEMINI_API_KEY` | Key of the Google Gemini AI. | `AIza…` or `AQ.…` |
| `UNSUBSCRIBE_HMAC_SECRET` | Random secret that signs the unsubscribe links. | `2891cd…` |

> **Never commit `.env` and never share it**: it contains your passwords. It is already listed in `.gitignore`. Do not change `N8N_ENCRYPTION_KEY` once n8n is running: n8n would no longer be able to read the secrets it stored.

### `SMTP_*`: a Gmail address to send the emails

We recommend a Gmail address created for the project. Gmail only accepts an **app password**, a 16-letter password made for one application:

1. Turn on **2-Step Verification** for the Google account: https://myaccount.google.com/signinoptions/twosv
2. Open https://myaccount.google.com/apppasswords, type a name such as `Persona n8n` and click **Create**.
3. Google shows a password of 16 letters in 4 groups. Copy it now: it is shown only once.
4. In `.env`:
   ```
   SMTP_HOST=smtp.gmail.com
   SMTP_PORT=465
   SMTP_USER=your.address@gmail.com
   SMTP_PASSWORD="abcd efgh ijkl mnop"
   ```
   Keep the quotes around the password because of the spaces.

> "App passwords" is missing from the Google page: 2-Step Verification is not turned on yet, or the account is managed by a school or a company that blocks it. Use a personal Gmail address.

Another provider works too: use its SMTP host, port (`465` with SSL, or `587`) and credentials.

### `GEMINI_API_KEY`: the AI

1. Open https://aistudio.google.com/apikey and sign in with a Google account.
2. Click **Create API key** (choose or create a project if asked), then **Copy**.
3. In `.env`:
   ```
   GEMINI_API_KEY=your-key
   ```

The free tier is enough. The workflows use the models `gemini-3.5-flash-lite` (summaries, newsletter) and `gemini-3.5-flash` (chat agent).

### `UNSUBSCRIBE_HMAC_SECRET`: the link signature

Generate a random secret in the terminal and copy the result into `.env`:
```bash
openssl rand -hex 32
```
```
UNSUBSCRIBE_HMAC_SECRET=the-64-characters-printed
```

**Check** that all 6 secret lines are filled (this prints the names only, never the values):
```bash
grep -E '^(SMTP_|GEMINI_|UNSUBSCRIBE_).+=.' .env | cut -d= -f1
```
You must see `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD`, `GEMINI_API_KEY` and `UNSUBSCRIBE_HMAC_SECRET`.

## 5. Load the secrets into n8n

```bash
make credentials
```

This creates the three n8n credentials every workflow uses (SMTP, Gemini, Crypto), with the secrets of your `.env`. Run it again whenever you change a secret.

**Check:** the command prints `Successfully imported 3 credentials.` In n8n, the **Credentials** page lists *Persona SMTP*, *Persona Gemini* and *Persona Crypto*.

> `Fill these values in .env first: …` means a value is missing or wrong in `.env`: fix the named lines and run the command again.

## 6. Import the workflows

```bash
make import
```

**Check:** the command prints `Successfully imported 24 workflows.` Refresh n8n: the **Overview** page lists them.

## 7. Create the database

1. In n8n, open the workflow **Setup DB**.
2. Click **Execute workflow** (bottom of the screen). All the nodes turn green.

**Check:** open **Overview → Data tables**: you see `users`, `sessions`, `articles` and `settings`.

Optional: to receive an email when an automatic workflow fails, open the `settings` table and type your email address in the `value` of the `alert_email` row.

## 8. Publish the workflows

A workflow only runs on its own (schedules, chat, links in the emails) once it is **published**. Importing leaves every workflow unpublished.

Open each workflow below **in this order** and click **Publish** (top right). The order matters: n8n refuses to publish a workflow before the workflows it calls. `Setup DB` is the only one you do not publish.

1. Auth - Check password
2. Auth - Check session
3. Auth - Create session
4. Auth - Send code
5. Data Retention
6. Error Handler
7. News Classify
8. Newsletter Build
9. Unsubscribe
10. Auth - Account
11. Auth - Export
12. Auth - Profile
13. Auth - Register
14. Auth - Resend
15. Auth - Session
16. Auth - Verify
17. News Fetch
18. Newsletter - Subscription
19. Newsletter Send
20. Newsletter - Request
21. Newsletter Scheduler
22. Auth - Router
23. Chat

**Check:** on the **Overview** page, all the workflows except `Setup DB` show as published.

## 9. Try it

1. Open **News Fetch** and click **Execute workflow** to fetch the first articles right away (otherwise wait for the next hour). Wait one minute: the articles get a summary.
2. Open the workflow **Chat** and click **Open chat** (bottom of the screen).
3. Write `Hello, I want to create an account` and follow the agent: accept the data notice, give an email address you can read, a password (8 characters minimum) and your language.
4. Copy the 6-digit code you receive by email into the chat (check the spam folder).
5. Write your interests and a time, for example `I like football and technology, send it every day at 8am`.
6. Write `Send me my newsletter now`: the newsletter arrives by email within a minute.

Wait about 20 seconds between two chat messages: the free Gemini quota is small per minute.

## Everyday use

| Command | What it does |
| --- | --- |
| `make up` | starts n8n |
| `make down` | stops n8n (nothing is lost) |
| `make logs` | shows what n8n is doing (Ctrl+C to quit) |
| `make credentials` | reloads the secrets of `.env` into n8n |
| `make import` | loads the workflows of the repository into n8n |
| `make export` | writes the workflows of n8n into `workflows/` |
| `make help` | lists these commands |

**After a `git pull`**, run `make import`, then publish the workflows again (step 8): importing unpublishes them.

**After editing a workflow in n8n**, click **Publish** again: the workflows that call it keep using the previously published version. To save your changes in the repository, run `make export` and commit only the files you changed.

Schedules only run while n8n is running: if the computer sleeps or Docker is stopped, nothing is fetched or sent.

## Troubleshooting

| Problem | Solution |
| --- | --- |
| `Cannot connect to the Docker daemon` | Start Docker Desktop (or the Docker service on Linux) and try again. |
| `make: command not found` | Install `make` (step 1). On Windows, run the commands in the Ubuntu terminal. |
| n8n refuses to publish a workflow | Publish the workflows it calls first (step 8 order). |
| "There was a problem executing the workflow" in the chat | Open the workflow's **Executions** tab to read the error. |
| `429 Too Many Requests` or `503 Service unavailable` from Gemini | The free quota is used up or Google is overloaded: wait a minute and try again. |
| No email arrives | Check the spam folder; check `SMTP_*` in `.env`, then run `make credentials` again. |
| `Could not find the data table` | Run **Setup DB** (step 7). |
| The unsubscribe link does not open | Open the email on the computer that runs n8n (the link points to `localhost`), and check that **Unsubscribe** is published. |
| A change made in n8n disappears | Keep only one browser tab per workflow, and refresh it before editing. |

## Production

To run Persona on a server reachable from the internet, also change the `public_url` row of the `settings` table to the public address of n8n (for example `https://persona.example.com`): the unsubscribe links of the emails use it.
