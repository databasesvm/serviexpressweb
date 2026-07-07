// supabase/functions/recuperar-contrasena/index.ts
// Variables de entorno en Supabase → Settings → Edge Functions:
//   RESEND_API_KEY  →  tu clave de resend.com

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { Resend } from 'npm:resend';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const { correo } = await req.json();

    if (!correo || typeof correo !== 'string') {
      return new Response(JSON.stringify({ error: 'Correo requerido' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    // 1. Buscar usuario por correo
    const { data: usuario } = await supabase
      .from('usuarios')
      .select('id, nombre')
      .eq('correo', correo.toLowerCase().trim())
      .maybeSingle();

    if (!usuario) {
      // Responder igual aunque no exista (evita enumeración de correos)
      return new Response(JSON.stringify({ ok: true }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // 2. Generar código 6 dígitos + expiración 15 min
    const codigo = Math.floor(100000 + Math.random() * 900000).toString();
    const expira = new Date(Date.now() + 15 * 60 * 1000).toISOString();

    // 3. Guardar en BD
    await supabase
      .from('usuarios')
      .update({ reset_token: codigo, reset_token_exp: expira })
      .eq('id', usuario.id);

    // 4. Enviar email via Resend SDK
    const resend = new Resend(Deno.env.get('RESEND_API_KEY'));
    await resend.emails.send({
      from: 'onboarding@resend.dev',
      to: correo.toLowerCase().trim(),
      subject: 'Código de recuperación — Serviexpress',
      html: `
        <div style="font-family:sans-serif;max-width:480px;margin:auto;padding:32px;">
          <h2 style="color:#111;">Recuperar contraseña</h2>
          <p>Hola <strong>${usuario.nombre ?? ''}</strong>,</p>
          <p>Usa este código para restablecer tu contraseña en Serviexpress:</p>
          <div style="font-size:36px;font-weight:bold;letter-spacing:8px;
                      color:#1a1a1a;background:#f4f4f4;padding:20px;
                      text-align:center;border-radius:8px;margin:24px 0;">
            ${codigo}
          </div>
          <p style="color:#666;font-size:13px;">
            Válido por <strong>15 minutos</strong>.<br>
            Si no solicitaste este código, ignora este correo.
          </p>
        </div>
      `,
    });

    return new Response(JSON.stringify({ ok: true }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });

  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
