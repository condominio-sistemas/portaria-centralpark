# Controle de Encomendas — versão online (Supabase + GitHub Pages)

```
online/
├── docs/              ← site publicado no GitHub Pages
│   ├── index.html     ← sistema da portaria (login, encomendas, administração)
│   ├── foto.html      ← página que o celular abre pelo QR code
│   └── config.js      ← endereço e chave pública do Supabase
└── supabase/
    └── schema.sql     ← estrutura do banco (rodar uma vez)
```

A versão em arquivo único (`../Controle de encomendas - Central Park.html`) continua funcionando sozinha, como alternativa.

## 1. Criar o projeto no Supabase

1. Crie uma conta em supabase.com e um **New project**.
   - Região: **South America (São Paulo)**.
   - Guarde a senha do banco num lugar seguro (o sistema não usa, mas o suporte pode precisar).
2. Menu **SQL Editor** → **New query** → cole todo o conteúdo de `supabase/schema.sql` → **Run**.
   Deve terminar com "Success. No rows returned".

## 2. Configurar o login

Em **Authentication → Sign In / Providers → Email**:

- **Enable Email provider**: ligado.
- **Confirm email**: **desligado**. Os e-mails dos porteiros são fictícios e ninguém recebe nada.
- **Allow new users to sign up**: **ligado**. O sistema usa isso para o administrador criar porteiros.
  Quem se cadastrar por fora do sistema não tem acesso a nada, porque o banco só libera quem está na lista de porteiros.

## 3. Criar o primeiro administrador (você)

1. **Authentication → Users → Add user → Create new user**
   - Email: `satyro@portaria.local` (o usuário de login será `satyro`)
   - Password: sua senha (mínimo 6 caracteres)
   - Marque **Auto Confirm User**
2. **SQL Editor**, rode:

   ```sql
   insert into public.porteiros (id, usuario, nome, papel)
   select id, 'satyro', 'Satyro', 'admin' from auth.users where email = 'satyro@portaria.local';
   ```

Os demais porteiros você cria pelo próprio sistema, na aba **Administração**.

> Se o Supabase recusar o e-mail `@portaria.local` ("email address invalid"), troque o domínio por outro que você controle (ex.: `portaria.seudominio.com.br`), tanto aqui quanto em `DOMINIO_USUARIOS` no `config.js`. Nenhum e-mail é enviado.

## 4. Preencher o `config.js`

Em **Project Settings → API Keys**, copie:

- **Project URL** → `SUPABASE_URL`
- **Publishable key** (`sb_publishable_...`) ou a antiga **anon public** → `SUPABASE_ANON_KEY`

**Nunca** use a chave *secret* / *service_role* no site.

## 5. Publicar no GitHub Pages

1. Crie um repositório **público** no GitHub (`encomendas.centralpark`) com o conteúdo da pasta `online/`.
2. **Settings → Pages → Build and deployment**: *Deploy from a branch*, branch `main`, pasta **`/docs`** → Save.
3. Em 1–2 minutos o sistema fica em `https://driellensatyro.github.io/encomendas.centralpark/`.

O código fica visível por ser repositório público, mas os dados não: eles ficam no Supabase, protegidos por login e pelas regras do banco.
**Nunca coloque backups `.json` no repositório.** O `.gitignore` já bloqueia esses arquivos.

## 6. Primeiro acesso e migração

1. Abra o endereço, entre com `satyro` e sua senha.
2. **Administração → Usuários**: crie um usuário para cada porteiro (nome, usuário, senha).
3. **Administração → Banco de dados → Importar backup da versão local**: escolha o `.json` mais recente gerado pela portaria na versão antiga.
   - Fotos, moradores, datas e status são importados.
   - Pode rodar de novo sem duplicar.
4. Na portaria:
   - abra o endereço no Chrome;
   - crie um atalho na área de trabalho (menu ⋮ → Transmitir, salvar e compartilhar → Criar atalho, marcando "Abrir como janela");
   - permita a câmera quando o navegador pedir.

## Funcionamento

- **Login por turno.** Cada porteiro entra com o próprio usuário e o turno começa ali. "Encerrar turno" registra a saída.
  - Se alguém fechar o navegador sem encerrar, o turno é fechado no próximo login dessa pessoa, com o horário da última atividade.
- **Autoria.** O banco registra quem cadastrou, quem deu baixa, quem enviou ou trocou a foto e quem excluiu, com data e hora.
  - Quem faz o registro é o servidor, então o navegador não consegue forjar a autoria.
  - Excluir não apaga de verdade: a encomenda some da tela, mas o registro fica guardado.
- **Foto pelo celular.** Em "📷 Foto" → "📱 Celular (QR code)":
  - o celular lê o código e tira a foto;
  - a foto aparece sozinha no computador;
  - o QR vale 15 minutos e serve para uma única foto;
  - o celular não precisa de login.
- **Tempo real.** Se houver mais de um computador, o que um faz aparece no outro.

## Custos e cuidados

- **Plano gratuito do Supabase**: 500 MB de banco e 1 GB de fotos (cerca de 10 mil fotos de 100 KB).
  - **Não tem backup automático.** Por isso o sistema baixa um backup `.json` por dia na pasta de downloads do computador da portaria. Mantenha essa pasta dentro do OneDrive.
  - As fotos **não** vão no `.json`.
  - O projeto gratuito é pausado após 7 dias sem uso. Com uso diário, isso não acontece.
- **Plano Pro**: US$ 25/mês, com backup diário automático e sem pausa. É a base para cobrar mensalidade.
- **LGPD**: nomes e telefones dos moradores ficam na nuvem. Convém o condomínio estar ciente e registrar o consentimento.
- **Internet**: sem internet, a portaria não consegue cadastrar. Um aviso aparece no topo da tela.
