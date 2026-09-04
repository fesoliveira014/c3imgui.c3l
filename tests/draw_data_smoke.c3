module draw_data_smoke;

import imgui;
import imgui::draw_list;

fn void assert_vec2(imgui::Vec2 actual, float x, float y)
{
    assert(actual[0] == x);
    assert(actual[1] == y);
}

fn imgui::Vec2 display_pos(imgui::DrawData draw_data)
{
    float x;
    float y;
    imgui::draw_data_display_pos(draw_data, &x, &y);
    imgui::Vec2 result = { x, y };
    return result;
}

fn imgui::Vec2 display_size(imgui::DrawData draw_data)
{
    float x;
    float y;
    imgui::draw_data_display_size(draw_data, &x, &y);
    imgui::Vec2 result = { x, y };
    return result;
}

fn imgui::Vec2 framebuffer_scale(imgui::DrawData draw_data)
{
    float x;
    float y;
    imgui::draw_data_framebuffer_scale(draw_data, &x, &y);
    imgui::Vec2 result = { x, y };
    return result;
}

fn void main()
{
    assert(imgui::draw_data_cmd_list((imgui::DrawData)null, 0) == null);
    assert(imgui::draw_list_vtx_ptr((imgui::DrawList)null) == null);
    assert(imgui::draw_list_vtx_count((imgui::DrawList)null) == -1);
    assert(imgui::draw_list_idx_ptr((imgui::DrawList)null) == null);
    assert(imgui::draw_list_idx_count((imgui::DrawList)null) == -1);
    assert(imgui::draw_list_cmd_ptr((imgui::DrawList)null) == null);
    assert(imgui::draw_list_cmd_count((imgui::DrawList)null) == -1);
    assert_vec2(display_pos((imgui::DrawData)null), -1.0f, -1.0f);
    assert_vec2(display_size((imgui::DrawData)null), -1.0f, -1.0f);
    assert_vec2(framebuffer_scale((imgui::DrawData)null), -1.0f, -1.0f);
    assert(imgui::draw_idx_size() == 2);

    imgui::Context context = imgui::create_context((imgui::FontAtlas)null);
    assert(context != null);
    defer imgui::destroy_context(context);

    imgui::io_set_ini_filename(null);

    imgui::io_set_display_size(320.0f, 200.0f);
    imgui::io_set_delta_time(1.0f / 60.0f);
    bool fonts_ready = imgui::fonts_build(imgui::io_get_fonts());
    assert(fonts_ready);

    imgui::new_frame();
    imgui::DrawList background = imgui::get_background_draw_list();
    imgui::Vec2 p0 = { 10.0f, 10.0f };
    imgui::Vec2 p1 = { 100.0f, 10.0f };
    imgui::Vec2 p2 = { 10.0f, 100.0f };
    imgui::draw_list::add_triangle_filled(background, p0, p1, p2, 0xffffffff);
    imgui::render();

    imgui::DrawData data = imgui::get_draw_data();
    assert(imgui::draw_data_valid(data));
    assert_vec2(display_pos(data), 0.0f, 0.0f);
    assert_vec2(display_size(data), 320.0f, 200.0f);
    assert_vec2(framebuffer_scale(data), 1.0f, 1.0f);

    int list_count = imgui::draw_data_cmd_list_count(data);
    assert(list_count > 0);
    assert(imgui::draw_data_cmd_list(data, -1) == null);
    assert(imgui::draw_data_cmd_list(data, list_count) == null);

    imgui::DrawList list = imgui::draw_data_cmd_list(data, 0);
    assert(list != null);
    int vertex_count = imgui::draw_list_vtx_count(list);
    int index_count = imgui::draw_list_idx_count(list);
    int command_count = imgui::draw_list_cmd_count(list);
    assert(vertex_count > 0);
    assert(index_count > 0);
    assert(command_count > 0);

    imgui::DrawVert* vertices = imgui::draw_list_vtx_ptr(list);
    imgui::DrawIdx* indices = imgui::draw_list_idx_ptr(list);
    imgui::DrawCmd* commands = imgui::draw_list_cmd_ptr(list);
    assert(vertices != null);
    assert(indices != null);
    assert(commands != null);
    imgui::Vec2 first_pos = vertices[0].pos;
    imgui::Vec2 first_uv = vertices[0].uv;
    imgui::DrawIdx first_index = indices[0];
    imgui::Vec4 first_clip = commands[0].clip_rect;
    assert(first_pos[0] >= 0.0f && first_pos[0] <= 320.0f);
    assert(first_pos[1] >= 0.0f && first_pos[1] <= 200.0f);
    assert(first_uv[0] >= 0.0f && first_uv[0] <= 1.0f);
    assert(first_uv[1] >= 0.0f && first_uv[1] <= 1.0f);
    assert(vertices[0].col == 0xffffffff);
    assert((uint)first_index < (uint)vertex_count);
    assert(commands[0].idx_offset == 0);
    assert(first_clip[2] >= first_clip[0] && first_clip[3] >= first_clip[1]);
    assert(commands[0].elem_count >= 3);
}
