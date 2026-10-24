import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
serve(async (req) => {
 if(req.method!=="POST") return new Response("Method not allowed",{status:405});
 const {booking_id,notification_token}=await req.json().catch(()=>({}));
 if(!booking_id||!notification_token) return Response.json({error:"Missing booking_id or notification_token"},{status:400});
 const url=Deno.env.get("SUPABASE_URL"),key=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
 if(!url||!key) return Response.json({error:"Server not configured"},{status:503});
 const db=createClient(url,key);
 const {data:b,error}=await db.from("bookings").select("*").eq("id",booking_id).eq("notification_token",notification_token).eq("status","confirmed").is("notifications_sent_at",null).maybeSingle();
 if(error||!b) return Response.json({error:"Booking not found or notification already processed"},{status:404});
 const token=Deno.env.get("WHATSAPP_ACCESS_TOKEN"),phoneId=Deno.env.get("WHATSAPP_PHONE_NUMBER_ID"),ownerRaw=Deno.env.get("BARBER_WHATSAPP");
 const template=Deno.env.get("WHATSAPP_TEMPLATE_NAME")||"booking_confirmation",language=Deno.env.get("WHATSAPP_TEMPLATE_LANGUAGE")||"pt_BR";
 if(!token||!phoneId||!ownerRaw) return Response.json({error:"WhatsApp API secrets not configured"},{status:503});
 const day=String(b.appointment_date).split("-").reverse().join("/"),time=String(b.appointment_time).slice(0,5),price=Number(b.price).toLocaleString("pt-BR",{style:"currency",currency:"BRL"});
 const params=[b.customer_name,b.service,day,time,price].map(text=>({type:"text",text:String(text)}));
 const send=async(to:string)=>{const r=await fetch(`https://graph.facebook.com/v22.0/${phoneId}/messages`,{method:"POST",headers:{Authorization:`Bearer ${token}`,"Content-Type":"application/json"},body:JSON.stringify({messaging_product:"whatsapp",to,type:"template",template:{name:template,language:{code:language},components:[{type:"body",parameters:params}]}})});const j=await r.json();if(!r.ok)throw new Error(JSON.stringify(j));return j};
 try{
  let customer=String(b.customer_phone).replace(/\D/g,"");if(!customer.startsWith("55"))customer="55"+customer;
  const owner=String(ownerRaw).replace(/\D/g,"");
  const results=await Promise.all([send(customer),send(owner)]);
  const {error:updateError}=await db.from("bookings").update({notifications_sent_at:new Date().toISOString()}).eq("id",b.id).is("notifications_sent_at",null);
  if(updateError)return Response.json({error:"Messages sent but status update failed"},{status:500});
  return Response.json({ok:true});
 }catch(e){return Response.json({error:"WhatsApp send failed",detail:String(e)},{status:502})}
});
