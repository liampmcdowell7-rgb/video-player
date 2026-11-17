//! Writes N synthetic Dolby Vision Profile 7 (FEL) RPUs as HEVC UNSPEC62 NAL units (with 0x7C01 header,
//! emulation prevention applied) to a file: repeated records of [u32 little-endian length][bytes].
//! They are NOT from a real disc: they are built from the library's own structures (see docs/spikes/DOLBY_VISION_P7.md,
//! "How representative is it").
use anyhow::{ensure, Result};
use dolby_vision::rpu::dovi_rpu::DoviRpu;
use dolby_vision::rpu::generate::GenerateConfig;
use dolby_vision::rpu::profiles::profile84::Profile84;
use dolby_vision::rpu::rpu_data_mapping::DoviNlqMethod;
use dolby_vision::rpu::rpu_data_nlq::RpuDataNlq;
use std::io::Write;

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().collect();
    let n: usize = args.get(1).map(|s| s.parse().unwrap()).unwrap_or(2400);
    let out = args.get(2).cloned().unwrap_or_else(|| "p7_rpus.bin".into());

    // CMv2.9 metadata, as on UHD Blu-ray (no CMv4.0 block): L1 + L2 trims + L5 + L6 from the generator defaults.
    let cfg_json = format!(
        r#"{{"cm_version":"V29","profile":"8.1","length":{n},"level6":{{"max_display_mastering_luminance":1000,"min_display_mastering_luminance":1,"max_content_light_level":1000,"max_frame_average_light_level":400}},"shots":[{{"start":0,"duration":{n}}}]}}"#
    );
    let cfg: GenerateConfig = serde_json::from_str(&cfg_json)?;
    let mut rpus = cfg.generate_rpu_list()?;
    ensure!(rpus.len() == n);

    let mut f = std::io::BufWriter::new(std::fs::File::create(&out)?);
    let mut total = 0usize;
    for (i, rpu) in rpus.iter_mut().enumerate() {
        rpu.dovi_profile = 7;
        rpu.modified = true;
        let h = &mut rpu.header;
        h.vdr_bit_depth_minus8 = 4; // 12-bit VDR
        h.el_spatial_resampling_filter_flag = true; // FEL/MEL: enhancement layer present
        h.disable_residual_flag = false;

        // A realistic-size mapping: 8 luma polynomial pieces, 2 MMR (order 3) chroma curves (borrowed from the library's own 8.4 table).
        let mut m = Profile84::rpu_data_mapping();
        let j = (i % 7) as u64;
        if let Some(p) = m.curves[0].polynomial.as_mut() {
            for c in p.poly_coef.iter_mut() { c[0] = (c[0] + j * 11) % 8_000_000; }
        }
        m.nlq_method_idc = Some(DoviNlqMethod::LinearDeadzone);
        m.nlq_num_pivots_minus2 = Some(0);
        m.nlq_pred_pivot_value = Some([0, 1023]);
        // FEL: non-trivial NLQ parameters (a MEL would be all zero / vdr_in_max_int = 1).
        let mut nlq = RpuDataNlq::default();
        for c in 0..3 {
            nlq.nlq_offset[c] = 128 + (c as u16) * 3 + (j as u16);
            nlq.vdr_in_max_int[c] = 0;
            nlq.vdr_in_max[c] = 6_000_000 + j * 1000 + c as u64 * 17;
            nlq.linear_deadzone_slope_int[c] = 0;
            nlq.linear_deadzone_slope[c] = 4_000_000 + c as u64 * 31;
            nlq.linear_deadzone_threshold_int[c] = 0;
            nlq.linear_deadzone_threshold[c] = 200_000 + c as u64 * 7;
        }
        m.nlq = Some(nlq);
        rpu.rpu_data_mapping = Some(m);

        let nal = rpu.write_hevc_unspec62_nalu()?;
        // Round trip: must parse back as profile 7 FEL.
        let back = DoviRpu::parse_unspec62_nalu(&nal)?;
        ensure!(back.dovi_profile == 7, "parsed back as profile {}", back.dovi_profile);
        if i == 0 {
            eprintln!("RPU 0: {} bytes, profile {}, el_type {:?}", nal.len(), back.dovi_profile, back.el_type);
        }
        total += nal.len();
        f.write_all(&(nal.len() as u32).to_le_bytes())?;
        f.write_all(&nal)?;
    }
    eprintln!("wrote {} RPUs, {} bytes total, mean {:.1} bytes", n, total, total as f64 / n as f64);
    Ok(())
}