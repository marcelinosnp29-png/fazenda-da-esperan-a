# 🌐 Fazenda da Esperança

> Quero construir uma pagina de formação para voluntários e acolhidos da Fazenda da Esperança no qual vou usar os links do youtube do  canal da Fazenda da Esperança

Ecossistema web completo gerado pelo **Agente Arquiteto Autônomo**.
Powered by Gemini AI + Supabase + GitHub Pages.

## Configuração em 4 Passos

### 1. Banco de Dados (Supabase)
1. Crie um projeto em [supabase.com](https://supabase.com) (gratuito)
2. Vá em **SQL Editor** e execute `supabase/schema.sql`
3. Copie a **Project URL** e **anon/public key** de Settings > API

### 2. Credenciais
Edite `assets/js/supabase-client.js`:
```js
const SUPABASE_URL = 'https://SEU-PROJETO.supabase.co';
const SUPABASE_KEY = 'SUA_CHAVE_ANON';
```
Faça o mesmo nos arquivos `admin/*.html`.

### 3. Usuário Admin
Supabase > Authentication > Users > Add User.

### 4. Hospedagem
**GitHub Pages** (gratuito): Settings > Pages > Source: main
URL: `https://marcelinosnp29-png.github.io/fazenda-da-esperan-a`

**Vercel** (recomendado): importe este repositório em [vercel.com](https://vercel.com)

---
Gerado por [Meu Agente AI](https://github.com) · Gemini + Supabase + GitHub Pages
