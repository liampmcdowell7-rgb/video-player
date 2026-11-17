//! FIXTURE generator for the Dolby Vision tests (scripts/test-dovi.sh copies this file into a scratch crate next to the
//! libdovi 3.3.2 source and builds it there; it is never part of the app).
//!
//! Writes synthetic RPU lists in the RPU.bin layout the reference CLI reads (each RPU = 00 00 00 01 + escaped RPU without its NAL header):
//!   rpu_p7_fel.bin  profile 7 FEL, CM v2.9, three shots with different L1/L2 and a per-frame L1 edit, L5 letterbox,
//!                   a non-identity luma polynomial + chroma MMR mapping and non-trivial NLQ (residual) parameters
//!   rpu_p7_mel.bin  profile 7 MEL, CM v4.0 (L8/L9/L11 defaults), same mapping, NLQ made "minimal" by the library itself
//!   rpu_p81.bin     profile 8.1, CM v4.0 (used for the second half of the "profile switches mid-stream" fixture)
//! Every RPU is parsed back and checked (profile, enhancement-layer type). None of this comes from a disc: the values are
//! invented, only the structure is real (see docs/DOLBY_VISION.md, "Test streams").
use anyhow::{ensure, Result};
use dolby_vision::rpu::dovi_rpu::DoviRpu;
use dolby_vision::rpu::generate::GenerateConfig;
use dolby_vision::rpu::profiles::profile84::Profile84;
use dolby_vision::rpu::rpu_data_mapping::DoviNlqMethod;
use dolby_vision::rpu::rpu_data_nlq::RpuDataNlq;
use std::io::Write;

fn config(n: usize, cm: &str) -> Result<GenerateConfig> {
    let a = n / 3;
    let b = n / 3;
    let c = n - a - b;
    let l2 = |max: u16, power: u16| format!(r#"{{"Level2":{{"target_max_pq":{max},"trim_slope":2048,"trim_offset":2048,"trim_power":{power},"trim_chroma_weight":2048,"trim_saturation_gain":2048,"ms_weight":2048}}}}"#);
    let l1 = |min: u16, max: u16, avg: u16| format!(r#"{{"Level1":{{"min_pq":{min},"max_pq":{max},"avg_pq":{avg}}}}}"#);
    let json = format!(
        r#"{{"cm_version":"{cm}","profile":"8.1","length":{n},"level5":{{"active_area_left_offset":0,"active_area_right_offset":0,"active_area_top_offset":40,"active_area_bottom_offset":40}},
"level6":{{"max_display_mastering_luminance":1000,"min_display_mastering_luminance":1,"max_content_light_level":1000,"max_frame_average_light_level":400}},
"shots":[
 {{"start":0,"duration":{a},"metadata_blocks":[{s1l1},{s1l2}],"frame_edits":[{{"edit_offset":5,"metadata_blocks":[{e1}]}}]}},
 {{"start":{a},"duration":{b},"metadata_blocks":[{s2l1},{s2l2}]}},
 {{"start":{ab},"duration":{c},"metadata_blocks":[{s3l1},{s3l2}]}}]}}"#,
        ab = a + b,
        s1l1 = l1(2, 2938, 1456), s1l2 = l2(2851, 1800), e1 = l1(0, 3079, 1229),
        s2l1 = l1(0, 2081, 820), s2l2 = l2(2851, 2048),
        s3l1 = l1(7, 3696, 2090), s3l2 = l2(3079, 2200),
    );
    Ok(serde_json::from_str(&json)?)
}

fn make_profile7(rpu: &mut DoviRpu, i: usize) {
    rpu.dovi_profile = 7;
    rpu.modified = true;
    let h = &mut rpu.header;
    h.vdr_bit_depth_minus8 = 4; // 12-bit VDR, as on UHD Blu-ray
    h.el_spatial_resampling_filter_flag = true;
    h.disable_residual_flag = false;
    let mut m = Profile84::rpu_data_mapping(); // a non-identity luma polynomial + chroma MMR, from the library's own table
    let j = (i % 7) as u64;
    if let Some(p) = m.curves[0].polynomial.as_mut() {
        for c in p.poly_coef.iter_mut() { c[0] = (c[0] + j * 11) % 8_000_000; }
    }
    m.nlq_method_idc = Some(DoviNlqMethod::LinearDeadzone);
    m.nlq_num_pivots_minus2 = Some(0);
    m.nlq_pred_pivot_value = Some([0, 1023]);
    let mut nlq = RpuDataNlq::default(); // FEL: a real residual (MEL would be offset 0, vdr_in_max_int 1, all else 0)
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
}

fn write(path: &str, rpus: &mut [DoviRpu], expect_profile: u8, expect_el: Option<&str>) -> Result<()> {
    let mut f = std::io::BufWriter::new(std::fs::File::create(path)?);
    let mut total = 0usize;
    for rpu in rpus.iter_mut() {
        // RPU.bin layout (as the reference tool's extract-rpu writes it): start code + the emulation-escaped RPU
        // without the 7C 01 NAL header (first byte 0x19), so no start code can appear inside.
        let full = rpu.write_hevc_unspec62_nalu()?;
        let back = DoviRpu::parse_unspec62_nalu(&full)?;
        let nal = full[2..].to_vec();
        ensure!(back.dovi_profile == expect_profile, "{path}: parsed back as profile {}", back.dovi_profile);
        let el = back.el_type.as_ref().map(|e| format!("{e:?}"));
        ensure!(el.as_deref() == expect_el, "{path}: enhancement layer {:?}, expected {:?}", el, expect_el);
        total += nal.len();
        f.write_all(&[0, 0, 0, 1])?;
        f.write_all(&nal)?;
    }
    eprintln!("{path}: {} RPUs, mean {:.1} bytes, profile {expect_profile}, EL {:?}", rpus.len(), total as f64 / rpus.len() as f64, expect_el);
    Ok(())
}

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().collect();
    let n: usize = args.get(1).map(|s| s.parse().unwrap()).unwrap_or(96);
    let dir = args.get(2).cloned().unwrap_or_else(|| ".".into());

    let mut fel = config(n, "V29")?.generate_rpu_list()?;
    for (i, r) in fel.iter_mut().enumerate() { make_profile7(r, i); }
    write(&format!("{dir}/rpu_p7_fel.bin"), &mut fel, 7, Some("FEL"))?;

    let mut mel = config(n, "V40")?.generate_rpu_list()?;
    for (i, r) in mel.iter_mut().enumerate() {
        make_profile7(r, i);
        r.convert_with_mode(1u8)?; // the library's own MEL conversion
    }
    write(&format!("{dir}/rpu_p7_mel.bin"), &mut mel, 7, Some("MEL"))?;

    let mut p81 = config(n, "V40")?.generate_rpu_list()?;
    write(&format!("{dir}/rpu_p81.bin"), &mut p81, 8, None)?;
    Ok(())
}
